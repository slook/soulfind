// SPDX-FileCopyrightText: 2024 Soulfind Contributors
// SPDX-FileCopyrightText: 2005-2017 SeeSchloss <seeschloss@seeschloss.org>
// SPDX-License-Identifier: GPL-3.0-or-later


module messages;
@safe:

import defines;

import std.bitmanip;
import std.conv : to;
import std.format : format;
import std.outbuffer : OutBuffer;
import std.stdio : writeln;

import message_codes;

class Message
{	// Server message
	uint code;
	OutBuffer out_buf;

	ubyte[] bytes()
	{
		return out_buf.toBytes();
	}

	this(uint code)
	{
		out_buf = new OutBuffer();
		this.code = code;
		writei(code);
	}

	private void writei(uint i)
	{
		out_buf.write(i);
	}

	private void writei(ulong i)
	{
		out_buf.write(cast(uint) i);
	}

	private void writesi(int i)
	{
		out_buf.write(i);
	}
		
	private void writeb(bool b)
	{
		out_buf.write(cast(ubyte) b);
	}
	
	private void writes(string s)
	{
		writei(s.length);
		out_buf.write(s);
	}

	uint length;
	ubyte[] in_buf;

	this(ubyte[] in_buf)
	{
		this.in_buf = in_buf;
	}

	private uint readi()
	{ // read an int
		uint i;
		if (in_buf.length < uint.sizeof)
		{
			writeln(
				"message code ", code, ", length ", length,
				" not enough data trying to read an int"
			);
			return i;
		}

		i = in_buf.read!(uint, Endian.littleEndian);
		return i;
	}

	private uint readsi()
	{ // read a signed int
		int i;
		if (in_buf.length < int.sizeof)
		{
			writeln(
				"message code ", code, ", length ", length,
				" not enough data trying to read a signed int"
			);
			return i;
		}

		i = in_buf.read!(int, Endian.littleEndian);
		return i;
	}
	
	private bool readb()
	{ // read a bool
		bool i;
		if (in_buf.length < bool.sizeof)
		{
			writeln(
				"message code ", code, ", length ", length,
				" not enough data trying to read a bool"
			);
			return i;
		}

		i = in_buf.read!(bool, Endian.littleEndian);
		return i;
	}
	
	private string reads()
	{ // read a string
		auto slen = readi();
		if (slen > in_buf.length) slen = cast(uint) in_buf.length;
		auto str = cast(string) in_buf[0 .. slen].idup;

		in_buf = in_buf[slen .. $];
		return str;
	}
}

class ULogin : Message
{		// New login
	string username;		// user name
	string password;		// user password
	uint   major_version;	// client version
	string hash;			// MD5 hash of username + password
	uint   minor_version;	// client minor version

	this(ubyte[] in_buf)
	{
		super(in_buf);

		username = reads();
		password = reads();
		major_version = readi();

		if (major_version >= 155) {
			// Older clients would not send these
			hash = reads();
			minor_version = readi();
		}
	}
}

class USetWaitPort : Message
{		// A client is telling us which port it is listening on
	uint port;	// port number
	this(ubyte[] in_buf)
	{
		super(in_buf);

		port = readi();
	}
}
	
class UGetPeerAddress : Message
{		// A client is asking for someone's address
	string user;	// name of the user to get the address of
	
	this(ubyte[] in_buf)
	{
		super(in_buf);

		user = reads();
	}
}

class UWatchUser : Message
{		// A client wants to watch a user
	string user;	// name of the user to watch

	this(ubyte[] in_buf)
	{
		super(in_buf);

		user = reads();
	}
}

class UUnwatchUser : Message
{		// A client wants to unwatch a user
	string user;	// name of the user to unwatch

	this(ubyte[] in_buf)
	{
		super(in_buf);

		user = reads();
	}
}

class UGetUserStatus : Message
{		// A client wants to know the status of someone
	string user;	// name of the user
	
	this(ubyte[] in_buf)
	{
		super(in_buf);

		user = reads();
	}
}

class USayChatroom : Message
{		// A client wants to say something in a chatroom
	string room;	// room to talk in
	string message;	// what to say
	
	this(ubyte[] in_buf)
	{
		super(in_buf);
		
		room   = reads();
		message = reads();
	}
}

class UJoinRoom : Message
{		// Client wants to join a room
	string room;	// room the client wants to join

	this(ubyte[] in_buf)
	{
		super(in_buf);

		room = reads();
	}
}

class ULeaveRoom : Message
{		// Client wants to leave a room
	string room;	// room the client wants to leave

	this(ubyte[] in_buf)
	{
		super(in_buf);

		room = reads();
	}
}

class UConnectToPeer : Message
{		// Client cannot connect to another one and wants us to
			// ask the other to connect to him
	uint token;	// connection token
	string user;	// user name
	string type;	// connection type("F" if for a file transfers, "P" otherwise)

	this(ubyte[] in_buf)
	{
		super(in_buf);

		token = readi();
		user  = reads();
		type  = reads();
	}
}

class UMessageUser : Message
{		// Client wants to send a private message
	string user;	// user to send the message to
	string message; // message content

	this(ubyte[] in_buf)
	{
		super(in_buf);

		user    = reads();
		message = reads();
	}
}

class UMessageAcked : Message
{		// Client acknowledges a private message
	uint id;	// message id
	
	this(ubyte[] in_buf)
	{
		super(in_buf);

		id = readi();
	}
}

class UFileSearch : Message
{		// Client makes a filesearch
	uint token;	// search token
	string strng;	// search string

	this(ubyte[] in_buf)
	{
		super(in_buf);

		token = readi();
		strng = reads();
	}
}

class UWishlistSearch : Message
{		// Client makes a wishlist search
	uint token;	// search token
	string strng;	// search string

	this(ubyte[] in_buf)
	{
		super(in_buf);

		token = readi();
		strng = reads();
	}
}

class USetStatus : Message
{		// Client sets its status
	uint status;	// 0 : Offline - 1 : Away - 2 : Online

	this(ubyte[] in_buf)
	{
		super(in_buf);

		status = readi();
	}
}

class USendUploadSpeed : Message
{		// Client reports a transfer speed
	uint    speed;  // speed

	this(ubyte[] in_buf)
	{
		super(in_buf);

		speed = readi();
	}
}

class USharedFoldersFiles : Message
{		// Client tells us how many files and folder it is sharing
	uint nb_folders;// number of folders
	uint nb_files;	// number of files

	this(ubyte[] in_buf)
	{
		super(in_buf);

		nb_folders = readi();
		nb_files   = readi();
	}
}

class UGetUserStats : Message
{		// Client wants the stats of someone
	string user;	// user name

	this(ubyte[] in_buf)
	{
		super(in_buf);

		user = reads();
	}
}

class UUserSearch : Message
{		// Client wants to send searches to his buddies...
	string user;	// user to send the search to(yes, there is one message to the server
			// sent for each buddy... how efficient [:kiki])
	uint   token;	// search token
	string query;	// search string

	this(ubyte[] in_buf)
	{
		super(in_buf);

		user  = reads();
		token = readi();
		query = reads();
	}
}

class UAddThingILike : Message
{		// Client likes thing
	string thing;	// thing(s)he likes

	this(ubyte[] in_buf)
	{
		super(in_buf);

		thing = reads();
	}
}

class URemoveThingILike : Message
{		// Client doesn't like thing anymore
	string thing;	// the thing

	this(ubyte[] in_buf)
	{
		super(in_buf);

		thing = reads();
	}
}

class UUserInterests : Message
{		// A user wants to know this user's likes and hates
	string user;

	this(ubyte[] in_buf)
	{
		super(in_buf);

		user = reads();
	}
}

class UAddThingIHate : Message
{		// Client hates thing
	string thing;	// thing(s)he likes

	this(ubyte[] in_buf)
	{
		super(in_buf);

		thing = reads();
	}
}

class URemoveThingIHate : Message
{		// Client doesn't hate thing anymore
	string thing;	// the thing

	this(ubyte[] in_buf)
	{
		super(in_buf);

		thing = reads();
	}
}

class UGetItemRecommendations : Message
{		// An user wants to get recommendations
			// for a particular item
	string item;

	this(ubyte[] in_buf)
	{
		super(in_buf);

		item = reads();
	}
}

class UItemSimilarUsers : Message
{		// An user wants to know who
			// likes a particular item
	string item;

	this(ubyte[] in_buf)
	{
		super(in_buf);

		item = reads();
	}
}

class USetRoomTicker : Message
{		// Client sets a new ticker for a room
	string room;	// room name
	string tick;	// ticker content

	this(ubyte[] in_buf)
	{
		super(in_buf);

		room = reads();
		tick = reads();
	}
}

class URoomSearch : Message
{		// Client wants to send a search to all the users in the room
	string room;	// room name
	uint   token;	// search token
	string query;	// search string

	this(ubyte[] in_buf)
	{
		super(in_buf);

		room  = reads();
		token = readi();
		query = reads();
	}
}

class UUserPrivileged : Message
        {               // Client wants to know if someone has privileges
        string user;    // user name

        this(ubyte[] buf)
                {
                super(buf);
        
                user = reads();
                }
        }

class UAdminMessage : Message
{		// An admin sends a message
	string mesg;	// the message

	this(ubyte[] in_buf)
	{
		super(in_buf);

		mesg = reads();
	}
}

class UGivePrivileges : Message
{		// Client wants to give privileges to somebody else
	string user;	// user to give the privileges to
	uint   time;	// time to give

	this(ubyte[] in_buf)
	{
		super(in_buf);

		user = reads();
		time = readi();
	}
}

class UChangePassword : Message
{		// A user wants to change their password
	string password;

	this(ubyte[] in_buf)
	{
		super(in_buf);

		password = reads();
	}
}

class UMessageUsers : Message
{			// Client wants to send private messages
	string[] users;		// users to send the message to
	string   message;	// message content

	this(ubyte[] in_buf)
	{
		super(in_buf);

		foreach (i ; 0 .. readi()) users ~= reads();
		message = reads();
	}
}

class UCantConnectToPeer : Message
{		// Client tells us he couldn't connect to someone
	uint token;	// message token
	string user;	// user who requested the connection

	this(ubyte[] in_buf)
	{
		super(in_buf);

		token = readi();
		user  = reads();
	}
}

class SLogin : Message
{	// If the login succeeded send the MOTD and the external IP of the client
		// if not, send the error message
	this(bool success, string mesg, uint addr = 0,
			string password = null, bool supporter = false)
	{
		super(Login);
		
		writeb(success);	// success(0 = fail / 1 = success)
		writes(mesg);		// server message
		if (success)
		{
			writei(addr);	// external IP address of the client
			writes(password);
			writeb(supporter);
		}
	}
}

class SGetPeerAddress : Message
{	// Send the address and port of user user
	this(string username, uint address, uint port, uint unknown = 0,
			uint obfuscated_port = 0)
	{
		super(GetPeerAddress);
		
		writes(username);	// username the address belongs to
		writei(address);	// IP address
		writei(port);		// port number
		writei(unknown);
		writei(obfuscated_port);
	}
}

class SWatchUser : Message
{	// Tell a client if a user exists and potential stats
	this(string user, bool exists, uint status, uint speed,
			uint upload_number, uint something, uint shared_files,
			uint shared_folders, string country_code)
	{
		super(WatchUser);

		writes(user);   // username
		writeb(exists); // whether the user exists or not
		if (!exists)
			return;

		writei(status);		// status
		writei(speed);			// speed(in B/s)
		writei(upload_number);		// upload number
		writei(something);		// something ?
		writei(shared_files);		// shared files
		writei(shared_folders);	// shared folders
		if (status > 0) writes(country_code);  // country code
	}
}

class SGetUserStatus : Message
{	// Send the status of user user
	this(string username, uint status, bool privileged)
	{
		super(GetUserStatus);

		writes(username);	// username
		writei(status);	// user status(see the class User)
		writeb(privileged);    // is user privileged
	}
}

class SSayChatroom : Message
{	// User user has said mesg in room room
	this(string room, string user, string mesg)
	{
		super(SayChatroom);

		writes(room); // room the message comes from
		writes(user); // the user who said it
		writes(mesg); // what(s)he said
	}
}

class SRoomList : Message
{	// Send the list of rooms
	this(ulong[string] rooms)
	{
		super(RoomList);
		
		writei(rooms.length);	// number of room names we will send
		foreach (room, users ; rooms) writes(room);
		
		writei(rooms.length);	// number of user counts
		foreach (room, users ; rooms) writei(users);

		writei(0);	// number of owned private rooms(unimplemented)
		writei(0);	// number of owned private rooms(unimplemented)
		writei(0);	// number of other private rooms(unimplemented)
		writei(0);	// number of other private rooms(unimplemented)
		writei(0);	// number of operated private rooms(unimplemented)
	}
}

class SJoinRoom : Message
{	// Give info on the room to a client who just joined it
	this(string room, string[] usernames, uint[string] statuses,
			uint[string] speeds, uint[string] upload_numbers,
			uint[string] somethings, uint[string] shared_files,
			uint[string] shared_folders, uint[string] slots_full,
			string[string] country_codes)
	{
		super(JoinRoom);

		writes(room);	// the room the user just joined
		auto n = usernames.length;

		writei(n);	// number of user names we will send
		foreach (username ; usernames) writes(username);
		
		writei(n);	// number of user statuses we will send
		foreach (username ; usernames) writei(statuses[username]);
		
		writei(n);	// number of stats we will send
		foreach (username ; usernames)
		{
			writei(speeds          [username]);	// speed of each user
			writei(upload_numbers	[username]);	// number of files uploaded ever
			writei(somethings      [username]);	// something ?
			writei(shared_files    [username]);	// nb of shared files
			writei(shared_folders  [username]);	// nb of shared folders
		}
		
		writei(n);	// number of slots records we will send...
		foreach (username ; usernames) writei(slots_full[username]);

		writei(n);	// number of country codes we will send
		foreach (username ; usernames) writes(country_codes[username]);
	}
}
	
class SLeaveRoom : Message
{	// Tell a client he has to leave a room
	this(string room)
	{
		super(LeaveRoom);

		writes(room);	// the room the user left
	}
}

class SUserJoinedRoom : Message
{	// User user has joined the room room
	this(string room, string username, uint status,
			uint speed, uint upload_number, uint something,
			uint shared_files, uint shared_folders,
			uint slots_full,string country_code)
	{
		super(UserJoinedRoom);

		writes(room);			// the room an user joined
		writes(username);		// name of the user who joined
		writei(status);		// status
		writei(speed);			// speed
		writei(upload_number);		// upload number
		writei(something);		// something ?
		writei(shared_files);		// shared files
		writei(shared_folders);	// shared folders
		writei(slots_full);		// slots full
		writes(country_code);		// country code
	}
}

class SUserLeftRoom : Message
{	// User user has left the room room
	this(string username, string room)
	{
		super(UserLeftRoom);

		writes(room);		// the room an user left
		writes(username);	// name of the user who left
	}
}

class SConnectToPeer : Message
{	// Ask a peer to connect back to user
	this(string username, string type, uint address, uint port,
			uint token, bool privileged, uint unknown = 0,
			uint obfuscated_port = 0)
	{
		super(ConnectToPeer);

		writes(username);	// username of the peer to connect to
		writes(type);		// type of the connection("F" if it's for a filetransfer, "P" otherwise)
		writei(address);	// IP address of the peer to connect to
		writei(port);		// port to use
		writei(token);		// message token
		writeb(privileged);    // is user privileged
		writei(unknown);
		writei(obfuscated_port);
	}
}

class SMessageUser : Message
{	// Send the PM
	this(uint id, uint timestamp, string from, string content,
			bool new_message)
	{
		super(MessageUser);

		writei(id);		// message id
		writei(timestamp);	// timestamp(seconds since 1970)
		writes(from);		// sender
		writes(content);	// message content
		writeb(new_message);
	}
}

class SFileSearch : Message
{	// Send a filesearch
	this(string username, uint token, string text)
	{
		super(FileSearch);

		writes(username);	// username of the one who is doing the search
		writei(token);		// search token
		writes(text);		// search string
	}
}

class SGetUserStats : Message
{	// Send the stats of user user
	this(string username, uint speed, uint upload_number, uint something,
			uint shared_files, uint shared_folders)
	{
		super(GetUserStats);

		writes(username);		// user name
		writei(speed);			// speed(in B/s)
		writei(upload_number);		// upload number
		writei(something);		// something ?
		writei(shared_files);		// shared files
		writei(shared_folders);	// shared folders
	}
}

class SGetRecommendations : Message
{	// Send the list of recommendations for this client
	this(uint[string] list)	// list[artist] = level
	{
		super(GetRecommendations);

		writei(list.length);	// if you can't guess, stop reading now !
		foreach (artist, level ; list)
		{
			writes(artist);	// artist name
			writesi(level);	// « level » of recommendation
		}
	}
}

class SGetGlobalRecommendations : Message
{	// Send the list of global recommendations
		// the code is exactly the same as for GetRecommendations.
	this(uint[string] list)
	{
		super(GlobalRecommendations);

		writei(list.length);	// if you can't guess, you should have stopped several lines ago...
		foreach (artist, level ; list)
		{
			writes(artist);	// artist name
			writesi(level);	// « level » of recommendation
		}
	}
}

class SUserInterests : Message
{	// Send a user's likes and hates
	this(string user, string[string] likes, string[string] hates)
	{
		super(UserInterests);

		writes(user);

		writei(likes.length);
		foreach (thing ; likes) writes(thing);

		writei(hates.length);
		foreach (thing ; hates) writes(thing);
	}
}

class SRelogged : Message
{	// Tell a client he has just logged from elsewhere before disconnecting it
	this()
	{
		super(Relogged);
	}
}

class SUserSearch : Message
{	// User user has sent a buddy search to a client
	this(string user, uint token, string query)
	{
		super(UserSearch);

		writes(user);		// name of the user who sent the search
		writei(token);		// search token
		writes(query);		// search string
	}
}

class SAdminMessage : Message
{	// Send an admin message
	this(string message)
	{
		super(AdminMessage);

		writes(message);	// the message
	}
}

class SCheckPrivileges : Message
{	// Tell a client how many seconds of privileges he has left
	this(uint time)
	{
		super(CheckPrivileges);

		writei(time);		// time left
	}
}

class SWishlistInterval	: Message
{
	this(uint interval)
	{
		super(WishlistInterval);

		writei(interval);	// interval in seconds for searches
	}
}

class SSimilarUsers : Message
{	// Send a list of users with similar tastes
	this(uint[string] list)
	{
		super(SimilarUsers);

		writei(list.length);
		foreach (user, weight ; list)
		{
			writes (user);
			writesi(weight);
		}
	}
}

class SGetItemRecommendations : Message
{	// Send a list of recommendations for a particular item
	this(string item, uint[string] list)
	{
		super(ItemRecommendations);

		writes(item);
		writei(list.length);

		foreach (recommendation, weight ; list)
		{
			writes (recommendation);
			writesi(weight);
		}
	}
}

class SItemSimilarUsers : Message
{	// Send a list of users who like an item
	this(string item, string[] list)
	{
		super(ItemSimilarUsers);

		writes(item);
		writei(list.length);
		foreach (user ; list) writes(user);
	}
}

class SRoomTicker : Message
{	// Send the ticker of room room
	this(string room, string[string] tickers)
	{
		super(RoomTicker);

		writes(room);			// name of the room
		writei(tickers.length);	// number of tickers
		foreach (string user, string ticker ; tickers)
		{
			writes(user);		// user name
			writes(ticker);	// ticker content
		}
	}
}

class SRoomTickerAdd : Message
{	// A ticker has been added to the room room by the user user
	this(string room, string user, string ticker)
	{
		super(RoomTickerAdd);

		writes(room);		// name of the room
		writes(user);		// user name
		writes(ticker);	// ticker content
	}
}

class SRoomTickerRemove : Message
{	// User user has removed his ticker from the room room
	this(string room, string user)
	{
		super(RoomTickerRemove);

		writes(room);		// name of the room
		writes(user);		// user name
	}
}

class SRoomSearch : Message
{	// User user has sent a room search
	this(string user, uint token, string query)
	{
		super(RoomSearch);

		writes(user);		// name of the user who sent the search
		writei(token);		// search token
		writes(query);		// search string
	}
}

class SUserPrivileged : Message
{	// Send the privileges status of user
	this(string username, bool privileged)
	{
		super(UserPrivileged);

		writes(username);	// user name
		writeb(privileged);	// user privileged
	}
}

class SChangePassword : Message
{	// Send the new password of a user
	this(string password)
	{
		super(ChangePassword);

		writes(password);	// user's password
	}
}

class SGlobalRoomMessage : Message
{	// User user has said mesg in room room
	this(string room, string user, string mesg)
	{
		super(GlobalRoomMessage);

		writes(room); // room the message comes from
		writes(user); // the user who said it
		writes(mesg); // what(s)he said
	}
}

class SCantConnectToPeer : Message
{	// A connection couldn't be established for some message
	this(uint token)
	{
		super(CantConnectToPeer);

		writei(token);	// token of the message
	}
}
