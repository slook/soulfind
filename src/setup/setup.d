// SPDX-FileCopyrightText: 2024-2026 Soulfind Contributors
// SPDX-FileCopyrightText: 2005-2017 SeeSchloss <seeschloss@seeschloss.org>
// SPDX-License-Identifier: GPL-3.0-or-later


module soulfind.setup.setup;
@safe:

import soulfind.db : Database;
import soulfind.defines : blue, bold, default_max_users, default_motd,
                          default_port, norm, pbkdf2_iterations, red,
                          RoomMemberType, RoomType, SearchFilterType, VERSION;
import soulfind.pwhash : create_salt, hash_password;
import std.array : Appender;
import std.compiler : name, version_major, version_minor;
import std.conv : ConvException, text, to;
import std.datetime : Clock, days, Duration, SysTime;
import std.stdio : readln, StdioException, stdout, write, writeln;
import std.string : chomp, count, join, replace, split, strip, toLower;

// ANSI control sequences
private enum cl = "\015\033[2K";  // clear line "\r\x1b[2K"
private enum up = "\033[1A";      // move upwards "\x1b[1A"

struct MenuItem
{
    string           index;
    string           label;
    void delegate()  action;
}

final class Setup
{
    private Database db;
    private uint num_actions;


    this(string db_filename)
    {
        this.db  = new Database(db_filename);
    }

    void show()
    {
        writeln(
            red, "\&hearts;", norm, " ",
            bold, "Soulfind server management tool", norm, "\n"
        );
        try main_menu();
        catch (StdioException e) writeln(e.msg, ". Exiting!");
    }

    bool backup_db(string filename)
    {
        return db.backup(filename);
    }

    private void log(T...)(T args)
    {
        writeln(args);
        num_actions++;
    }

    @trusted
    private static string input()
    {
        stdout.flush();
        return readln();
    }

    private static void clearup(ulong n = 1)
    {
        for (uint l = 0; l < n; ++l)
            write(up, cl);  // "\033[1A\015\033[2K"
    }

    private static void show_menu(string heading, MenuItem[] items)
    {
        writeln("\r", heading, "\n");

        foreach (ref item; items) {
            const index = item.index;
            writeln(index, ".", index.length > 1 ? " " : "  ", item.label);
        }
        writeln("\n");

        while (true) {
            clearup();
            write(">", norm, " ");
            const choice = input.strip;

            if (choice is null)
                throw new StdioException("Terminal input unavailable");

            write(cl);

            foreach (ref item; items) {
                bool is_return = (choice == "" && item.label == "Return");

                if (choice != item.index && !is_return)
                    continue;

                clearup(items.length + count(heading, "\n") + 4);
                write(bold, item.label, ":", norm);

                item.action();
                return;
            }
            write(red, "Try a number with an action assigned to it!", norm);
        }
    }

    private void main_menu()
    {
        show_menu(
            text(bold, "Main Menu", norm),
            [
                MenuItem("1", "Admins",            &admins),
                MenuItem("2", "Registered users",  &registered_users),
                MenuItem("3", "Listening port",    &listening_port),
                MenuItem("4", "Private mode",      &private_mode),
                MenuItem("5", "Max users allowed", &max_users),
                MenuItem("6", "MOTD",              &motd),
                MenuItem("7", "Search filters",    &search_filters),
                MenuItem("i", "Server info",       &server_info),
                MenuItem("q", "Exit",              &exit)
            ]
        );
    }

    private void exit()
    {
        log("\n\tTotal actions done: ", bold, num_actions, norm);
    }

    private void admins()
    {
        show_menu(
            text(bold, "Admins (", db.num_users("admin"), ")", norm),
            [
                MenuItem("1", "Add/renew an admin", &add_admin),
                MenuItem("2", "Remove an admin",    &del_admin),
                MenuItem("3", "List admins",        &list_admins),
                MenuItem("q", "Return",             &main_menu)
            ]
        );
    }

    private void add_admin()
    {
        write("\nAdmin to add: ");
        const username = input.strip;

        Duration duration;
        while (true) {
            try {
                write("Number of days of admin status: ");
                const value = input.strip.to!ulong;
                enum limit = ushort.max;
                duration = (value > limit ? limit : value).days;
                break;
            }
            catch (ConvException) {
                write(red, "Invalid number or too many days!", norm);
                clearup();
            }
        }
        write(cl);
        clearup(2);

        if (db.add_admin(username, duration))
            log(
                "\tMade ", blue, username, norm, " an admin until ",
                db.admin_until(username).toSimpleString, "\n"
            );
        else
            writeln("\tUser ", red, username, norm, " is not registered\n");

        admins();
    }

    private void del_admin()
    {
        write("\nAdmin to remove: ");
        const username = input.strip;

        clearup();

        if (db.del_admin(username))
            log("\tUser ", blue, username, norm, " is no longer an admin\n");
        else
            writeln("\tUser ", red, username, norm, " is not an admin\n");

        admins();
    }

    private void list_admins()
    {
        const names = db.usernames("admin");
        const now = Clock.currTime;

        Appender!string output;
        foreach (ref name ; names) {
            const admin_until = db.admin_until(name);
            output ~= "\n\t";
            output ~= name;

            if (admin_until > now)
                output ~= text(" (until ", admin_until.toSimpleString, ")");
            else
                output ~= text(" (expired)");
        }
        output ~= "\n";

        writeln(output[]);
        admins();
    }


    private void listening_port()
    {
        show_menu(
            text(bold, "Listening port: ", blue, db.server_port, norm),
            [
                MenuItem("1", "Change listening port", &set_listening_port),
                MenuItem("2", "Reset listening port",  &reset_listening_port),
                MenuItem("q", "Return",                &main_menu)
            ]
        );
    }

    private void set_listening_port()
    {
        write("\nNew listening port: ");

        const value = input.strip;
        ushort port;

        try {
            port = value.to!ushort;
        }
        catch (ConvException) {
            write(red, "Enter port in range ", 1, "-", ushort.max, "!", norm);
            clearup();
            write(up);  // (up, cl, up)
            set_listening_port();
            return;
        }
        clearup();
        log(
            "\tPort (was ", db.server_port, ") changed to ",
            blue, port, norm, "\n", cl
        );
        db.set_server_port(port);
        listening_port();
    }

    private void reset_listening_port()
    {
        log(
            "\n\tPort (was ", db.server_port, ") changed to ",
            blue, default_port, norm, "\n"
        );
        db.set_server_port(default_port);
        listening_port();
    }

    private void private_mode()
    {
        show_menu(
            text(
                bold, "Private mode: ",
                db.server_private_mode ?
                text(
                    blue, "enabled", norm,
                    "\n\tNot accepting user registrations."
                ) :
                text(
                    red, "disabled", norm,
                    "\n\tAccepting user registrations."
                )
            ),
            [
                MenuItem("1", "Toggle private mode", &toggle_private_mode),
                MenuItem("q", "Return",              &main_menu)
            ]
        );
    }

    private void toggle_private_mode()
    {
        bool old_mode = db.server_private_mode;
        db.set_server_private_mode(!old_mode);
        log(
            "\n\tPrivate mode (was ", old_mode ? "enabled" : "disabled",
            ") changed to ", db.server_private_mode ?
            text(blue, "enabled") : text(red, "disabled"), norm, "\n"
        );
        private_mode();
    }

    private void max_users()
    {
        show_menu(
            text(bold, "Max users allowed: ", blue, db.server_max_users, norm),
            [
                MenuItem("1", "Change max users", &set_max_users),
                MenuItem("2", "Reset max users",  &reset_max_users),
                MenuItem("q", "Return",           &main_menu)
            ]
        );
    }

    private void set_max_users()
    {
        write("\nNew max users allowed: ");

        const value = input.strip;
        uint num_users;
        try {
            num_users = value.to!uint;
        }
        catch (ConvException) {
            write(red, "Please enter a valid number!", norm);
            clearup();
            write(up);  // (up, cl, up)
            set_max_users();
            return;
        }
        clearup();
        log(
            "\tMax users (was ", db.server_max_users, ") changed to ",
            blue, num_users, norm, "\n", cl
        );
        db.set_server_max_users(num_users);
        max_users();
    }

    private void reset_max_users()
    {
        log(
            "\n\tMax users (was ", db.server_max_users, ") changed to ",
            blue, default_max_users, norm, "\n"
        );
        db.set_server_max_users(default_max_users);
        max_users();
    }

    private void motd()
    {
        show_menu(
            text(bold, "Message of the day:", norm, "\n", db.server_motd),
            [
                MenuItem("1", "Change MOTD", &set_motd),
                MenuItem("2", "Reset MOTD",  &reset_motd),
                MenuItem("q", "Return",      &main_menu)
            ]
        );
    }

    private void set_motd()
    {
        auto prompt = text(
            "\nAvailable variables:",
            "\n\t%%sversion%% - server version (", VERSION, ")",
            "\n\t%%users%%    - number of connected users",
            "\n\t%%username%% - name of the connecting user",
            "\n\t%%version%%  - version of the user's client software",
            "\n\nNew MOTD (end with a dot on a single line):"
        );
        writeln(prompt);

        Appender!string motd_template;
        auto first = true;
        while (true) {
            const line = input.chomp;
            if (line.strip == ".")
                break;
            if (!first) motd_template ~= "\n";
            motd_template ~= line;
            first = false;
        }

        db.set_server_motd(motd_template[]);

        const nlines = count(motd_template[], "\n") + (first ? 0 : 1);
        clearup(count(prompt, "\n") + nlines + 1);
        log("\t", nlines, " lines, ", motd_template[].length, " characters\n");

        motd();
    }

    private void reset_motd()
    {
        log("\n\t", default_motd.length, " characters\n");
        db.set_server_motd(default_motd);
        motd();
    }

    private void search_filters()
    {
        enum server = SearchFilterType.server;
        enum client = SearchFilterType.client;

        show_menu(
            text(
                bold, "Search filters", norm,
                "\n\tfiltered users: ",      db.num_users("unsearchable"),
                "\n\tserver-side phrases: ", db.num_search_filters!server,
                "\n\tclient-side phrases: ", db.num_search_filters!client
            ),
            [
                MenuItem("1", "Filter user",            &filter_user),
                MenuItem("2", "Unfilter user",          &unfilter_user),
                MenuItem("3", "Filter server phrase",   &add_filter!server),
                MenuItem("4", "Unfilter server phrase", &del_filter!server),
                MenuItem("5", "Filter client phrase",   &add_filter!client),
                MenuItem("6", "Unfilter client phrase", &del_filter!client),
                MenuItem("7", "List filtered users",    &list_filtered_users),
                MenuItem("8", "List server phrases",    &list_filters!server),
                MenuItem("9", "List client phrases",    &list_filters!client),
                MenuItem("q", "Return",                 &main_menu)
            ]
        );
    }

    private void filter_user()
    {
        write(" ");
        const username = input.strip;

        if (db.set_user_unsearchable(username))
            log("\tFiltered user ", blue, username, norm, "\n");
        else
            writeln("\tUser ", red, username, norm, " is not registered\n");

        search_filters();
    }

    private void unfilter_user()
    {
        write(" ");
        const username = input.strip;

        if (db.set_user_searchable(username))
            log("\tUnfiltered user ", blue, username, norm, "\n");
        else
            writeln("\tUser ", red, username, norm, " is not filtered\n");

        search_filters();
    }

    private void add_filter(SearchFilterType type)()
    {
        write(" ");
        const phrase = input.split.join(" ").toLower;

        db.filter_search_phrase!type(phrase);
        log("\tFiltered phrase ", blue, phrase, norm, "\n");

        search_filters();
    }

    private void del_filter(SearchFilterType type)()
    {
        write(" ");
        const phrase = input.split.join(" ").toLower;

        if (db.unfilter_search_phrase!type(phrase))
            log("\tUnfiltered phrase ", blue, phrase, norm, "\n");
        else
            writeln("\tPhrase ", red, phrase, norm, " is not filtered\n");

        search_filters();
    }

    private void list_filtered_users()
    {
        const names = db.usernames("unsearchable");

        Appender!string output;
        foreach (ref name ; names) {
            output ~= "\n\t";
            output ~= name;
        }
        output ~= "\n";

        writeln(output[]);
        search_filters();
    }

    private void list_filters(SearchFilterType type)()
    {
        const phrases = db.search_filters!type;

        Appender!string output;
        foreach (phrase ; phrases) {
            output ~= "\n\t";
            output ~= phrase;
        }
        output ~= "\n";

        writeln(output[]);
        search_filters();
    }

    private void registered_users()
    {
        const now = Clock.currTime.toUnixTime;
        show_menu(
            text(
                bold, "Registered users (", db.num_users, ")", norm,
                "\n\tprivileged: ", db.num_users("privileges", now),
                "\n\tbanned: ", db.num_users("banned", now)
            ),
            [
                MenuItem("1",  "Add user",              &add_user),
                MenuItem("2",  "Change user password",  &change_user_password),
                MenuItem("3",  "Show user info",        &user_info),
                MenuItem("4",  "Export user data",      &export_user_data),
                MenuItem("5",  "Remove user",           &del_user),
                MenuItem("6",  "Add privileges",        &add_privileges),
                MenuItem("7",  "Remove privileges",     &del_privileges),
                MenuItem("8",  "Ban user",              &ban_user),
                MenuItem("9",  "Unban user",            &unban_user),
                MenuItem("10", "List registered users", &list_registered),
                MenuItem("11", "List privileged users", &list_privileged),
                MenuItem("12", "List banned users",     &list_banned),
                MenuItem("q",  "Return",                &main_menu)
            ]
        );
    }

    private void add_user()
    {
        write("\nUsername: ");
        const username = input.strip;

        if (username.length == 0) {
            // writeln("\nNo username provided");
            clearup(2);
            registered_users();
            return;
        }

        string password;
        while (true) {
            write("Password: ");
            password = input.chomp;
            if (password.length > 0)
                break;
            write(red, "Please enter a password!", norm);
            clearup();
        }
        clearup();
        write("Password: ", blue, "***", norm, " hashing...");

        const salt = create_salt();
        const hash = hash_password(password, salt, pbkdf2_iterations);

        clearup();

        if (db.add_user(username, hash))
            log("\tAdded user ", blue, username, norm, "\n");
        else
            writeln("\tUser ", red, username, norm, " already exists\n");

        registered_users();
    }

    private void change_user_password()
    {
        write("\nUser to change password of: ");
        const username = input.strip;

        string password;
        while (true) {
            write("New password: ");
            password = input.chomp;
            if (password.length > 0)
                break;
            write(red, "Please enter a password!", norm);
            clearup();
        }
        clearup();
        write("New password: ", blue, "***", norm, " hashing...");

        const salt = create_salt();
        const hash = hash_password(password, salt, pbkdf2_iterations);

        clearup();

        if (db.update_user_password(username, hash))
            log("\tChanged user ", blue, username, norm, "'s password\n");
        else
            writeln("\tUser ", red, username, norm, " is not registered\n");

        registered_users();
    }

    private void user_info()
    {
        write(" ");

        const username = input.strip;
        const stats = db.user_stats(username);

        if (!stats.exists) {
            writeln("\tUser ", red, username, norm, " is not registered\n");
            registered_users();
            return;
        }

        const now = Clock.currTime;
        const admin_until = db.admin_until(username);
        const admin = (admin_until > now)
            ? text("until ", admin_until.toSimpleString) : "no";
        const banned_until = db.user_banned_until(username);
        auto banned = "no";
        const privileged_until = db.user_privileged_until(username);
        const privileged = (privileged_until > now)
            ? text("until ", privileged_until.toSimpleString) : "no";
        const supporter = (privileged_until > SysTime.init) ? "yes" : "no";
        const searchable = db.is_user_unsearchable(username) ? "no" : "yes";
        const rooms_owner = db.owned_rooms(username).join(", ");
        const rooms_member = db.member_rooms!(RoomMemberType.any)(
            username).join(", ");
        const rooms_operator = db.member_rooms!(RoomMemberType.operator)(
            username).join(", ");
        const tickers = db.user_tickers!(RoomType.any)(username);

        if (banned_until == SysTime.max)
            banned = "forever";

        else if (banned_until > now)
            banned = text("until ", banned_until.toSimpleString);

        Appender!string output;
        output ~= text(
            // "\n", bold, username, norm,
            "\tusername: ", bold, username, norm,
            "\n\tadmin: ", admin,
            "\n\tbanned: ", banned,
            "\n\tprivileged: ", privileged,
            "\n\tsupporter: ", supporter,
            "\n\tsearchable: ", searchable,
            "\n\tfiles: ", stats.shared_files,
            "\n\tfolders: ", stats.shared_folders,
            "\n\tupload speed: ", stats.upload_speed,
            "\n\towned rooms: ", rooms_owner,
            "\n\tmember rooms: ", rooms_member,
            "\n\toperated rooms: ", rooms_operator,
            "\n\troom tickers: "
        );

        if (tickers.length > 0) {
            foreach (ticker ; tickers)
                output ~= text(
                    "\n\t   [", ticker.room_name, "] ", ticker.content
                );
        }

        output ~= "\n";
        writeln(output[]);
        registered_users();
    }

    private void export_user_data()
    {
        write(" ");

        const username = input.strip;
        const stats = db.user_stats(username);

        if (!stats.exists) {
            writeln("\tUser ", red, username, norm, " is not registered\n");
            registered_users();
            return;
        }

        enum quot = "\"";
        enum d_quot = "\"\"";
        enum j_quot = "\", \"";

        const admin_until = db.admin_until(username);
        const admin = (admin_until > SysTime.init)
            ? text(quot, admin_until.toISOExtString, quot)
            : "null";

        const banned_until = db.user_banned_until(username);
        const banned = (banned_until > SysTime.init)
            ? text(quot, banned_until.toISOExtString, quot)
            : "null";

        const privileged_until = db.user_privileged_until(username);
        const privileged = (privileged_until > SysTime.init)
            ? text(quot, privileged_until.toISOExtString, quot)
            : "null";

        const supporter = (privileged_until > SysTime.init) ? "true" : "false";
        const searchable = (
            db.is_user_unsearchable(username) ? "false" : "true"
        );

        string rooms(bool is_owner = true) {
            Appender!string output;
            const rooms = is_owner
                ? db.owned_rooms(username)
                : db.member_rooms!(RoomMemberType.any)(username);

            if (rooms.length == 0)
                return output[];

            auto first = true;
            foreach (ref room_name ; rooms) {
                const owner = db.get_room_owner(room_name);
                const members = text(
                    quot, db.room_members!(RoomMemberType.any)(room_name)
                    .join(j_quot), quot
                ).replace(d_quot, "");

                const operators = text(
                    quot, db.room_members!(RoomMemberType.operator)(room_name)
                    .join(j_quot), quot
                ).replace(d_quot, "");

                if (!first) output ~= ",";
                output ~= text(
                    "\n            {",
                    "\n                \"room_name\": \"", room_name, "\",",
                    "\n                \"owner\": \"", owner, "\",",
                    "\n                \"members\": [", members, "],",
                    "\n                \"operators\": [", operators, "]",
                    "\n            }"
                );
                first = false;
            }
            output ~= "\n        ";
            return output[];
        }

        string tickers() {
            Appender!string output;
            const tickers = db.user_tickers!(RoomType.any)(username);
            if (tickers.length == 0)
                return output[];

            auto first = true;
            foreach (ticker ; tickers) {
                const name = ticker.room_name;
                const content = ticker.content;

                if (!first) output ~= ",";
                output ~= text(
                    "\n            {",
                    "\n                \"room_name\": \"", name, "\",",
                    "\n                \"content\": \"", content, "\"",
                    "\n            }"
                );
                first = false;
            }
            output ~= "\n        ";
            return output[];
        }

        writeln(
            // blue, username, norm, "'s persistent data in JSON format",
            "{",
            "\n    \"username\": \"", username, "\",",
            "\n    \"persistent_data\": {",
            "\n        \"admin_until\": ", admin, ",",
            "\n        \"banned_until\": ", banned, ",",
            "\n        \"privileged_until\": ", privileged, ",",
            "\n        \"supporter\": ", supporter, ",",
            "\n        \"searchable\": ", searchable, ",",
            "\n        \"num_files\": ", stats.shared_files, ",",
            "\n        \"num_folders\": ", stats.shared_folders, ",",
            "\n        \"upload_speed\": ", stats.upload_speed, ",",
            "\n        \"private_rooms_owner\": {", rooms, "}",
            "\n        \"private_rooms_member\": {", rooms(false), "}",
            "\n        \"room_tickers\": {", tickers, "}",
            "\n    }",
            "\n}",
            "\n"
        );
        registered_users();
    }

    private void del_user()
    {
        write(" ");
        const username = input.strip;

        if (db.del_user(username))
            log("\tRemoved user ", blue, username, norm, "\n");
        else
            writeln("\tUser ", red, username, norm, " is not registered\n");

        registered_users();
    }

    private void add_privileges()
    {
        write("\nUser to grant privileges: ");
        const username = input.strip;

        Duration duration;
        while (true) {
            try {
                write("Number of days to add: ");
                const value = input.strip.to!ulong;
                enum limit = ushort.max;
                duration = (value > limit ? limit : value).days;
                break;
            }
            catch (ConvException) {
                write(red, "Invalid number or too many days!", norm);
                clearup();
            }
        }
        write(cl);
        clearup(2);

        if (db.add_user_privileges(username, duration))
            log(
                "\tAdded ", duration.total!"days".days.toString,
                " of privileges to user ", blue, username, norm, "\n"
            );
        else
            writeln("\tUser ", red, username, norm, " is not registered\n");

        registered_users();
    }

    private void del_privileges()
    {
        write("\nUser to remove privileges from: ");
        const username = input.strip;

        Duration duration;
        while (true) {
            write("Number of days to remove (empty = all): ");
            const user_input = input.strip;

            if (user_input.length == 0) {
                duration = Duration.max;
                break;
            }

            try {
                const value = user_input.to!ulong;
                enum limit = ushort.max;
                duration = (value > limit ? limit : value).days;
                break;
            }
            catch (ConvException) {
                write(red, "Invalid number or too many days!", norm);
                clearup();
            }
        }
        write(cl);
        clearup(2);

        if (!db.remove_user_privileges(username, duration))
            writeln("\tUser ", red, username, norm, " has no privileges\n");
        else if (duration == Duration.max)
            log(
                "\tRemoved all privileges from user ", blue, username, norm,
                "\n"
            );
        else
            log(
                "\tRemoved ", duration.total!"days".days.toString,
                " of privileges from user ", blue, username, norm, "\n"
            );

        registered_users();
    }

    private void ban_user()
    {
        write(" ");
        const username = input.strip;

        Duration banned_until;
        while (true) {
            write("Number of days to ban user (empty = forever): ");
            const duration = input.strip;

            if (duration.length == 0) {
                banned_until = Duration.max;
                break;
            }

            try {
                banned_until = duration.to!uint.days;
                break;
            }
            catch (ConvException) {
                write(red, "Invalid number or too many days!", norm);
                clearup();
            }
        }
        clearup();

        if (!db.ban_user(username, banned_until))
            writeln("\tUser ", red, username, norm, " is not registered\n");
        else if (banned_until == Duration.max)
            log("\tBanned user ", blue, username, norm, " forever\n");
        else
            log(
                "\tBanned user ", blue, username, norm, " for ",
                banned_until.toString, "\n"
            );

        registered_users();
    }

    private void unban_user()
    {
        write(" ");
        const username = input.strip;

        if (db.unban_user(username))
            log("\tUnbanned user ", blue, username, norm, "\n");
        else
            writeln("\tUser ", red, username, norm, " is not banned\n");

        registered_users();
    }

    private void list_registered()
    {
        const names = db.usernames;

        Appender!string output;
        foreach (ref name ; names) {
            output ~= "\n\t";
            output ~= name;
        }
        output ~= "\n";

        writeln(output[]);
        registered_users();
    }

    private void list_privileged()
    {
        const names = db.usernames("privileges", Clock.currTime.toUnixTime);

        Appender!string output;
        foreach (ref name ; names) {
            const privileged_until = db.user_privileged_until(name);
            output ~= "\n\t";
            output ~= name;
            output ~= text(" (until ", privileged_until.toSimpleString, ")");
        }
        output ~= "\n";

        writeln(output[]);
        registered_users();
    }

    private void list_banned()
    {
        const names = db.usernames("banned", Clock.currTime.toUnixTime);

        Appender!string output;
        foreach (ref name ; names) {
            const banned_until = db.user_banned_until(name);
            if (banned_until != SysTime.max) {
                output ~= "\n\t";
                output ~= name;
                output ~= text(" (until ", banned_until.toSimpleString, ")");
            }
            else {
                output ~= "\n\t";
                output ~= name;
                output ~= " (forever)";
            }
        }
        output ~= "\n";

        writeln(output[]);
        registered_users();
    }

    private void server_info()
    {
        writeln(
            "\n\t", red, "\&hearts;", norm, " ", bold, "Soulfind ", VERSION,
            norm, "\n\tCompiled with ", name, " ",
            version_major, ".", version_minor,
            "\n\tUsing SQLite ", db.sqlite_version, "\n"
        );
        main_menu();
    }
}
