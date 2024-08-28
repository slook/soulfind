// SPDX-FileCopyrightText: 2024 Soulfind Contributors
// SPDX-FileCopyrightText: 2005-2017 SeeSchloss <seeschloss@seeschloss.org>
// SPDX-License-Identifier: GPL-3.0-or-later


module defines;
@safe:

const string VERSION		= "0.5.0-dev";
const string default_db_file	= "soulfind.db";
const uint port			= 2242;
const uint max_users		= 65535;
const uint max_msg_size		= 16384;
const string server_user	= "server";

// colours
const char[] norm	= "\033[0m";		// reset to normal
const char[] bold	= "\033[1m";		// bold intensity
const char[] bg_w	= "\033[30;107m";	// background white
const char[] blue	= "\033[01;94m";	// foreground blue
const char[] red	= "\033[01;91m";	// foreground red
