// SPDX-FileCopyrightText: 2024 Soulfind Contributors
// SPDX-FileCopyrightText: 2005-2017 SeeSchloss <seeschloss@seeschloss.org>
// SPDX-License-Identifier: GPL-3.0-or-later


module server;
@safe:

import defines;

import client;
import messages, message_codes;
import db;
import room;
import pm;

import std.stdio : writefln;
import std.socket;
import std.conv : ConvException, to;
import std.array : split, join, replace;
import std.ascii : isPrintable, isPunctuation;
import std.format : format;
import std.algorithm : canFind;
import std.digest : digest, LetterCase, toHexString, secureEqual;
import std.digest.md : MD5;
import std.string : strip;
import std.process : thisProcessID;
import std.exception : ifThrown;

import core.sys.posix.unistd : fork;
import core.sys.posix.signal;
import core.time : Duration, MonoTime, minutes, seconds;

extern(C) void handle_termination(int)
{
	writefln("\nA la prochaine...");
}

@trusted
private void setup_signal_handler()
{
	sigaction_t act;
	act.sa_handler = &handle_termination;

	sigaction(SIGINT, &act, null);
	sigaction(SIGTERM, &act, null);
}

private void help(string[] args)
{
	writefln("Usage: %s [database_file] [-d|--daemon]", args[0]);
	writefln(
		"\tdatabase_file: path to the sqlite3 database (default: %s)",
		default_db_file
	);
	writefln("\t-d, --daemon : fork in the background");
}

private int main(string[] args)
{
	bool daemon;
	string db = default_db_file;

	if (args.length > 3) help(args);

	foreach (arg ; args[1 .. $]) {
		switch (arg) {
			case "-h":
			case "--help":
				help(args);
				return 0;
			case "-d":
			case "--daemon":
				daemon = true;
				break;
			default:
				db = arg;
				break;
		}
	}

	if (daemon && fork())
		return 0;

	setup_signal_handler();

	auto server = new Server(db);
	return server.listen();
}

class Server
{
	Sdb						db; 						// users database

	private ushort			port;
	private uint			max_users;

	private MonoTime		started_at;					// for server uptime

	private Socket			sock;
	private User[Socket]	user_socks;
	private auto			keepalive_time = 60;
	private auto			keepalive_interval = 5;
	private Duration		select_timeout = 2.minutes;

	private this(string db_file)
	{
		started_at = MonoTime.currTime;
		db = new Sdb(db_file);

		port = db.get_config_value("port").to!ushort.ifThrown(
			cast(ushort) default_port
		);
		max_users = db.get_config_value("max_users").to!uint.ifThrown(
			default_max_users
		);
	}

	private int listen()
	{
		sock = new TcpSocket();
		sock.blocking = false;
		sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

		try {
			sock.bind(new InternetAddress(port));
			sock.listen(10);
		}
		catch (SocketOSException e) {
			writefln("Unable to bind socket to port %d", port);
			if (port < 1024) writefln(
				"Are you trying to use a port less than "
				~ "1024 while running as a user ?"
			);
			return 1789;
		}

		writefln(
			"%s %s process %s listening on port %s",
			bg_w ~ "▌" ~ red ~ "♥" ~ norm ~ bg_w ~ "▐" ~ norm ~ bold
			~ "Soulfind", VERSION ~ norm, thisProcessID, port
		);

		auto read_socks = new SocketSet(max_users + 1);
		auto write_socks = new SocketSet(max_users + 1);

		while (true) {
			read_socks.reset();
			write_socks.reset();
			read_socks.add(sock);

			foreach (user_sock, user ; user_socks) {
				read_socks.add(user_sock);
				if (user.is_sending) write_socks.add(user_sock);
			}

			auto nb = Socket.select(
				read_socks, write_socks, null, select_timeout
			);
			const terminating = (nb == -1);

			if (read_socks.isSet(sock)) {
				while (true) {
					Socket new_sock;
					try {
						new_sock = sock.accept();
					}
					catch (SocketAcceptException) {
						break;
					}
					new_sock.setKeepAlive(keepalive_time, keepalive_interval);
					new_sock.setOption(
						SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1
					);
					new_sock.blocking = false;

					debug (user) writefln(
						"Connection accepted from %s", new_sock.remoteAddress
					);
					auto user = new User(
						this, new_sock,
						(cast(InternetAddress) new_sock.remoteAddress).addr
					);
					user_socks[new_sock] = user;
				}
				nb--;
				read_socks.remove(sock);
			}

			foreach (user_sock, user ; user_socks) {
				if (nb == 0)
					break;

				auto recv_success = true;
				auto send_success = true;
				bool changed;

				if (read_socks.isSet(user_sock)) {
					recv_success = user.recv_buffer();
					changed = true;
				}
				if (write_socks.isSet(user_sock)) {
					send_success = user.send_buffer();
					changed = true;
				}

				if (user.should_quit && !user.is_sending) {
					send_success = false;
				}

				if (changed) nb--;
				if (!terminating && recv_success && send_success)
					continue;

				read_socks.remove(user_sock);
				write_socks.remove(user_sock);
				del_user(user);
			}

			if (terminating)
				break;
		}

		sock.close();
		return 0;
	}

	// Filesearches
	void do_FileSearch(uint token, string query, string username)
	{
		auto msg = new SFileSearch(username, token, query);
		send_to_all(msg);
	}

	void do_UserSearch(uint token, string query, string username, string to)
	{
		auto msg = new SFileSearch(username, token, query);
		auto user = get_user(to);
		if (!user)
			return;

		user.send_message(msg);
	}

	void do_RoomSearch(uint token, string query, string username,
						string room_name)
	{
		auto msg = new SFileSearch(username, token, query);
		auto room = Room.get_room(room_name);
		if (!room)
			return;

		room.send_to_all(msg);
	}

	// Users
	private User[string] user_list;

	void add_user(User user)
	{
		user_list[user.username] = user;
	}

	bool find_user(User user)
	{
		return (user.username in user_list) ? true : false;
	}

	User get_user(string username)
	{
		if (username in user_list)
			return user_list[username];

		return null;
	}

	@trusted  // .keys doesn't work with @safe in old D versions
	User[] users()
	{
		return user_list.values;
	}

	private void del_user(User user)
	{
		if (user.sock in user_socks) {
			user.sock.shutdown(SocketShutdown.BOTH);
			user.sock.close();
			user_socks.remove(user.sock);
		}
		if (user.username in user_list) {
			user.quit();
			user_list.remove(user.username);
		}
	}

	private void send_to_all(Message msg)
	{
		debug (msg) writefln(
			"Transmit=> %s (code %d) to all users...",
			blue ~ message_name[msg.code] ~ norm, msg.code
		);
		foreach (user ; users) user.send_message(msg);
	}

	void admin_message(User admin, string message)
	{
		if (!db.is_admin(admin.username))
			return;

		const command = message.split(" ");
		if (command.length > 0) switch (command[0])
		{
			case "help":
				admin_pm(
					admin,
					"Available commands :\n\n"
				  ~ "users\n\tList connected users\n\n"
				  ~ "info <user>\n\tInfo about user <user>\n\n"
				  ~ "kickall\n\tDisconnect all users\n\n"
				  ~ "kick <user>\n\tDisconnect <user>\n\n"
				  ~ "[un]ban <user>\n\tUnban or ban and disconnect"
				  ~ " user <user>\n\n"
				  ~ "admins\n\tList admins\n\n"
				  ~ "rooms\n\tList rooms and number of"
				  ~ " occupiants\n\n"
				  ~ "addprivileges <days> <user>\n\tAdd <days>"
				  ~ " days of privileges to user <user>\n\n"
				  ~ "message <message>\n\tSend global message"
				  ~ " <message>\n\n"
				  ~ "uptime\n\tShow server uptime\n\n"
				);
				break;

			case "addprivileges":
				if (command.length < 3) {
					admin_pm(admin, "Syntax is : addprivileges <days> <user>");
					break;
				}

				uint days;
				try {
					days = command[1].to!uint;
				}
				catch (ConvException e) {
					admin_pm(admin, "Badly formatted number.");
					break;
				}

				const username = join(command[2 .. $], " ");
				auto user = get_user(username);
				if (!user) {
					admin_pm(
						admin, "User %s does not exist.".format(username)
					);
					break;
				}

				user.add_privileges(days * 3600 * 24);
				break;

			case "users":
				string list = "%d connected users.".format(user_list.length);
				foreach (username, user ; user_list) list ~= "\n\t" ~ username;
				admin_pm(admin, list);
				break;

			case "info":
				if (command.length < 2) {
					admin_pm(admin, "Syntax is : info <user>");
					break;
				}
				const username = join(command[1 .. $], " ");
				const user_info = show_user(username);
				admin_pm(admin, user_info);
				break;

			case "kickall":
				debug (user) writefln(
					"Admin %s kicks ALL users...", blue ~ admin.username ~ norm
				);
				kick_all_users();
				break;

			case "kick":
				if (command.length < 2) {
					admin_pm(admin, "Syntax is : kick <user>");
					break;
				}
				const username = join(command[1 .. $], " ");
				kick_user(username);
				admin_pm(
					admin, "User %s kicked from the server".format(username)
				);
				break;

			case "ban":
				if (command.length < 2) {
					admin_pm(admin, "Syntax is : ban <user>");
					break;
				}
				const username = join(command[1 .. $], " ");
				ban_user(username);
				admin_pm(
					admin, "User %s banned from the server".format(username)
				);
				break;

			case "unban":
				if (command.length < 2) {
					admin_pm(admin, "Syntax is : unban <user>");
					break;
				}
				const username = join(command[1 .. $], " ");
				unban_user(username);
				admin_pm(
					admin, "User %s not banned anymore".format(username)
				);
				break;

			case "admins":
				const names = db.admins;
				string list = "%d registered admins.".format(names.length);
				foreach (name ; names) list ~= "\n\t%s".format(name);
				admin_pm(admin, list);
				break;

			case "rooms":
				string list;
				foreach (room ; Room.rooms)
					list ~= "%s:%d ".format(room.name, room.nb_users);
				admin_pm(admin, list);
				break;

			case "message":
				if (command.length < 2) {
					admin_pm(admin, "Syntax is : message <message>");
					break;
				}
				const msg = join(command[1 .. $], " ");
				global_message(msg);
				break;

			case "uptime":
				admin_pm(admin, h_uptime);
				break;

			default:
				admin_pm(
					admin,
					"Don't expect me to understand what you want if you don't "
				  ~ "use a correct command..."
				);
				break;
		}
	}

	private void admin_pm(User admin, string message)
	{
		PM pm = new PM(message, server_user, admin.username);
		bool new_message = true;
		admin.send_pm(pm, new_message);
	}

	private void global_message(string message)
	{
		foreach (User user ; user_list) {
			user.send_message(new SAdminMessage(message));
		}
	}

	private string show_user(string username)
	{
		auto user = get_user(username);
		if (!user)
			return "";

		return format(
			"%s: connected at %s"
			~ "\n\tclient version: %s"
			~ "\n\taddress: %s"
			~ "\n\tadmin: %s"
			~ "\n\tfiles: %s"
			~ "\n\tdirs: %s"
			~ "\n\tstatus: %s"
			~ "\n\tprivileges: %s"
			~ "\n\tjoined rooms: %s",
				username,
				user.connected_at,
				"%d.%d".format(user.major_version, user.minor_version),
				user.sock.remoteAddress,
				db.is_admin(username),
				user.shared_files,
				user.shared_folders,
				user.status,
				user.h_privileges,
				user.list_joined_rooms
		);
	}

	private void kick_all_users()
	{
		foreach (user ; user_list) user.quit();
	}

	private void kick_user(string username)
	{
		auto user = get_user(username);
		if (user) user.quit();
	}

	private void ban_user(string username)
	{
		if (!db.user_exists(username))
			return;

		db.user_update_field(username, "banned", 1);
		kick_user(username);
	}

	private void unban_user(string username)
	{
		if (db.user_exists(username))
			db.user_update_field(username, "banned", 0);
	}

	string get_motd(User user)
	{
		string motd;
		const motd_template = db.get_config_value("motd");
		const client_version = "%d.%d".format(
			user.major_version, user.minor_version);

		motd = replace(motd_template, "%sversion%", VERSION);
		motd = replace(motd, "%users%", user_list.length.to!string);
		motd = replace(motd, "%username%", user.username);
		motd = replace(motd, "%version%", client_version);
		return motd;
	}

	private Duration uptime()
	{
		return MonoTime.currTime - started_at;
	}

	private string h_uptime()
	{
		return uptime.total!"seconds".seconds.toString;
	}

	string encode_password(string pass)
	{
		return digest!MD5(pass).toHexString!(LetterCase.lower).to!string;
	}

	bool check_name(string text, uint max_length = 24)
	{
		if (!text || text.length > max_length) {
			return false;
		}
		foreach (dchar c ; text) if (!isPrintable(c)) {
			// non-ASCII control chars, etc
			return false;
		}
		if (text.length == 1 && isPunctuation(text.to!dchar)) {
			// only character is a symbol
			return false;
		}
		if (strip(text) != text) {
			// leading/trailing whitespace
			return false;
		}

		const string[] forbidden_names = [server_user, ""];
		const string[] forbidden_words = ["  ", "sqlite3_"];

		foreach (name ; forbidden_names) if (name == text) {
			return false;
		}
		foreach (word ; forbidden_words) if (canFind(text, word)) {
			return false;
		}
		return true;
	}

	string check_login(string username, string password)
	{
		if (!check_name(username, 30))
			return "INVALIDUSERNAME";

		if (!db.user_exists(username)) {
			debug (user) writefln(
				"New user %s registering", blue ~ username ~ norm
			);
			db.add_user(username, encode_password(password));
			return null;
		}
		debug (user) writefln("User %s is registered", blue ~ username ~ norm);

		if (db.is_banned(username))
			return "BANNED";

		if (!secureEqual(db.get_pass(username), encode_password(password)))
			return "INVALIDPASS";

		return null;
	}
}
