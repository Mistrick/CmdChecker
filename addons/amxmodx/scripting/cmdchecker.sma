#include <amxmodx>

#define PLUGIN "Advanced Client Checker"
#define VERSION "0.3.4f"
#define AUTHOR "Mistrick"

#pragma semicolon 1

///******** Settings ********///

// #define KICK_BAD_CLIENT // кик за блокировку подтверждения
// #define KICK_FOR_BLOCK_CVAR_ANSWER // кик за блок ответа на запрос квара
// #define COMMAND_LOGGER // функция логирования написанных в консоль команд игроком

#define INPUT_DELAY 3.0 // задержка проверки после коннекта
#define RECHECK_DELAY 300.0 // через сколько начать повторную проверку
#define MAX_CMDS_FOR_LOOP 1000 // сколько команд проверять за цикл
#define LOOP_DELAY 5.0 // задержка между циклами
#define FIRST_ANSWER_MAX_TIME 5.0 // время на ответ от команды подтверждения
#define FIRST_CMD_RECHECKS 5
#define MAX_CMD_WARNINGS 5

#define CVAR_ANSWER_TIME 5.0 // время на ответ от квара
#define CVAR_ANSWER_RECHECKS 5 // число перепроверок на запрос квара

///**************************///

enum ( +=100 ) {
	TASK_FIRST_CMD = 100,
	TASK_CMD_CHECK,
	TASK_CVAR_ANSWER,
	TASK_CVAR_CHECK
};

enum CvarFlags( <<= 1 ) {
	CVAR_EXIST = 1,
	CVAR_NOT_EXIST,
	CVAR_EQUAL,
	CVAR_NOT_EQUAL,
	CVAR_ABOVE,
	CVAR_BELOW
}

enum PunishType {
	PUNISH_BAD_CLIENT,
	PUNISH_BLOCK_CVAR_ANSWER,
	PUNISH_WRONG_CMD,
	PUNISH_WRONG_CVAR,
	PUNISH_BAD_CMD
};

enum _:CommandStruct {
	_CmdPunishLevel,
	_Cmd[64]
};

enum _:CvarStruct {
	_CvarPunishLevel,
	CvarFlags:_CvarFlags,
	_Cvar[64],
	_CvarValue[32],
	Float:_CvarValueAbove,
	Float:_CvarValueBelow
};

enum BadCmdFlags ( <<= 1 ) {
	BADCMD_ANY = 1,
	BADCMD_PREFIX,
	BADCMD_SUFFIX
};

enum _:BadCmdStruct {
	_BadCmdPunishLevel,
	BadCmdFlags:_BadCmdFlags,
	_BadCmd[64]
};

enum _:PunishStruct {
	_PunishLevel,
	_PunishCmd[128]
};

#define CMD_LEN 16
#define INVALID_INDEX -1

new const FILE_CMD_CFG[] = "cmds.cfg";
new const FILE_CVAR_CFG[] = "cvars.cfg";
new const FILE_BAD_CMD_CFG[] = "bad_cmds.cfg";
new const FILE_PUNISH_CFG[] = "punish.cfg";
new const FILE_SLOWHACK_ANSWER_CFG[] = "slowhackanswer.cfg";

new player_authid[33][32];
new bool:is_player_steam[33];

new bool:client_answered[33];
new client_answer_check[33];
new client_cmd_warnings[33];
new current_cmd_state[33];
new current_cmd[33][64];
new bool:first_check[33];
new rnd_str[33][CMD_LEN];

new Array:g_aCmdList;
new g_iCmdListSize;

new Array:g_aBadCmdList;
new g_iBadCmdListSize;
new current_bad_cmd[33];

new current_cvar_state[33];
new client_cvar_warnings[33];

new Array:g_aCvarList;
new g_iCvarListSize;

new Array:g_aPunishList;

new Trie:g_tSlowhackAnswer;
new g_iSlowhackAnswerSize;

#if defined COMMAND_LOGGER
new const FILE_CMD_LOG[] = "cmdlog.cfg";
new Trie:g_tCmdLog;
new g_szCmdLogPath[260];
#endif // COMMAND_LOGGER

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	register_concmd("acc_add_cmd", "command_add_cmd", ADMIN_RCON);
	register_concmd("acc_add_cvar", "command_add_cvar", ADMIN_RCON);
	register_concmd("acc_add_bad_cmd", "command_add_bad_cmd", ADMIN_RCON);
	register_concmd("acc_add_punish", "command_add_punish", ADMIN_RCON);
	register_concmd("acc_add_slowhack_answer", "command_add_slowhack_answer", ADMIN_RCON);
	
	g_aCmdList = ArrayCreate(CommandStruct, 1);
	g_aCvarList = ArrayCreate(CvarStruct, 1);
	g_aBadCmdList = ArrayCreate(BadCmdStruct, 1);
	g_aPunishList = ArrayCreate(PunishStruct, 1);
	g_tSlowhackAnswer = TrieCreate();
	
	#if defined COMMAND_LOGGER
	register_concmd("acc_add_cmd_log", "command_add_cmd_log", ADMIN_RCON);
	g_tCmdLog = TrieCreate();
	#endif // COMMAND_LOGGER
}
public plugin_cfg()
{
	new file_dir[256]; get_localinfo("amxx_configsdir", file_dir, charsmax(file_dir));

	server_cmd("exec %s/cmdchecker/%s", file_dir, FILE_CMD_CFG);
	server_cmd("exec %s/cmdchecker/%s", file_dir, FILE_CVAR_CFG);
	server_cmd("exec %s/cmdchecker/%s", file_dir, FILE_BAD_CMD_CFG);
	server_cmd("exec %s/cmdchecker/%s", file_dir, FILE_PUNISH_CFG);
	server_cmd("exec %s/cmdchecker/%s", file_dir, FILE_SLOWHACK_ANSWER_CFG);
	
	#if defined COMMAND_LOGGER
	formatex(g_szCmdLogPath, charsmax(g_szCmdLogPath), "%s/cmdchecker/%s", file_dir, FILE_CMD_LOG);
	server_cmd("exec %s", g_szCmdLogPath);
	#endif // COMMAND_LOGGER
}
public plugin_end()
{
	ArrayDestroy(g_aCmdList);
	ArrayDestroy(g_aCvarList);
	ArrayDestroy(g_aPunishList);
	
	#if defined COMMAND_LOGGER
	TrieDestroy(g_tSlowhackAnswer);
	#endif // COMMAND_LOGGER
}
public command_add_cmd(id, level, cid)
{
	if(~get_user_flags(id) & level) {
		return PLUGIN_HANDLED;
	}
	
	if(read_argc() != 3) {
		return PLUGIN_HANDLED;
	}
	
	new cmd_info[CommandStruct], args[16];
	read_argv(1, args, charsmax(args));
	cmd_info[_CmdPunishLevel] = str_to_num(args);
	read_argv(2, cmd_info[_Cmd], charsmax(cmd_info[_Cmd]));
	trim(cmd_info[_Cmd]);
	
	ArrayPushArray(g_aCmdList, cmd_info);
	g_iCmdListSize++;
	
	return PLUGIN_HANDLED;
}
public command_add_cvar(id, level, cid)
{
	if(~get_user_flags(id) & level) {
		return PLUGIN_HANDLED;
	}
	
	new args_num = read_argc() - 1;
	
	if(args_num < 3) {
		return PLUGIN_HANDLED;
	}
	
	new cvar_info[CvarStruct], args[16];
	read_argv(1, args, charsmax(args));
	cvar_info[_CvarPunishLevel] = str_to_num(args);
	
	
	// find this cvar in array
	// if exists update cvar flags
	
	read_argv(2, cvar_info[_Cvar], charsmax(cvar_info[_Cvar]));
	trim(cvar_info[_Cvar]);
	strtolower(cvar_info[_Cvar]);
	
	read_argv(3, args, charsmax(args));
	
	if(args_num == 3) {
		if(equal(args, "exist")) {
			cvar_info[_CvarFlags] |= CVAR_EXIST;
		} else if(equal(args, "!exist")) {
			cvar_info[_CvarFlags] |= CVAR_NOT_EXIST;
		}
	} else if(args_num == 4) {
		if(equal(args, "equal") || equal(args, "==") || equal(args, ">=") || equal(args, "<=")) {
			cvar_info[_CvarFlags] |= CVAR_EQUAL;
			read_argv(4, cvar_info[_CvarValue], charsmax(cvar_info[_CvarValue]));
		} else if(equal(args, "!equal") || equal(args, "!=")) {
			cvar_info[_CvarFlags] |= CVAR_NOT_EQUAL;
			read_argv(4, cvar_info[_CvarValue], charsmax(cvar_info[_CvarValue]));
		}
		
		if(equal(args, ">") || equal(args, ">=")) {
			cvar_info[_CvarFlags] |= CVAR_ABOVE;
			read_argv(4, args, charsmax(args));
			cvar_info[_CvarValueAbove] = _:str_to_float(args);
		} else if(equal(args, "<") || equal(args, "<=")) {
			cvar_info[_CvarFlags] |= CVAR_BELOW;
			read_argv(4, args, charsmax(args));
			cvar_info[_CvarValueBelow] = _:str_to_float(args);
		}
	}
	
	if(cvar_info[_CvarFlags]) {
		ArrayPushArray(g_aCvarList, cvar_info);
		g_iCvarListSize++;
	}
	
	return PLUGIN_HANDLED;
}

public command_add_bad_cmd(id, level, cid)
{
	if(~get_user_flags(id) & level) {
		return PLUGIN_HANDLED;
	}
	
	if(read_argc() < 3) {
		return PLUGIN_HANDLED;
	}
	
	new bad_cmd_info[BadCmdStruct], args[16];
	read_argv(1, args, charsmax(args));
	bad_cmd_info[_BadCmdPunishLevel] = str_to_num(args);
	
	new command[64], len;
	len = read_argv(2, command, charsmax(command));
	
	if(command[0] == '*' && command[len - 1] == '*') {
		bad_cmd_info[_BadCmdFlags] = _:BADCMD_ANY;
		command[len - 1] = 0;
		copy(bad_cmd_info[_BadCmd], charsmax(bad_cmd_info[_BadCmd]), command[1]);
	} else if(command[0] != '*' && command[len - 1] != '*') {
		bad_cmd_info[_BadCmdFlags] = _:BADCMD_ANY;
		copy(bad_cmd_info[_BadCmd], charsmax(bad_cmd_info[_BadCmd]), command);
	} else if(command[0] == '*') {
		bad_cmd_info[_BadCmdFlags] = _:BADCMD_SUFFIX;
		copy(bad_cmd_info[_BadCmd], charsmax(bad_cmd_info[_BadCmd]), command[1]);
	} else if(command[len - 1] == '*') {
		bad_cmd_info[_BadCmdFlags] = _:BADCMD_PREFIX;
		command[len - 1] = 0;
		copy(bad_cmd_info[_BadCmd], charsmax(bad_cmd_info[_BadCmd]), command);
	}
	
	ArrayPushArray(g_aBadCmdList, bad_cmd_info);
	g_iBadCmdListSize++;
	
	return PLUGIN_HANDLED;
}

public command_add_punish(id, level, cid)
{
	if(~get_user_flags(id) & level) {
		return PLUGIN_HANDLED;
	}
	
	if(read_argc() != 3) {
		return PLUGIN_HANDLED;
	}
	
	new punish_info[PunishStruct], args[16];
	read_argv(1, args, charsmax(args));
	punish_info[_PunishLevel] = str_to_num(args);
	read_argv(2, punish_info[_PunishCmd], charsmax(punish_info[_PunishCmd]));
	
	ArrayPushArray(g_aPunishList, punish_info);
	
	return PLUGIN_HANDLED;
}
public command_add_slowhack_answer(id, level, cid)
{
	if(~get_user_flags(id) & level) {
		return PLUGIN_HANDLED;
	}
	
	new args[64]; read_args(args, charsmax(args));
	remove_quotes(args); trim(args);
	TrieSetCell(g_tSlowhackAnswer, args, 1);
	g_iSlowhackAnswerSize++;
	
	return PLUGIN_HANDLED;
}

#if defined COMMAND_LOGGER
public command_add_cmd_log(id, level, cid)
{
	if(~get_user_flags(id) & level) {
		return PLUGIN_HANDLED;
	}
	
	new args[64]; read_args(args, charsmax(args));
	remove_quotes(args); trim(args);
	TrieSetCell(g_tCmdLog, args, 1);
	
	return PLUGIN_HANDLED;
}
#endif // COMMAND_LOGGER

public client_putinserver(id)
{
	if(is_user_bot(id) || is_user_hltv(id)) return;
	
	is_player_steam[id] = is_user_steam(id);
	
	if(g_iCmdListSize) {
		client_answer_check[id] = 0;
		set_task(INPUT_DELAY + random_float(0.5, 1.5), "init_cmd_check", id + TASK_CMD_CHECK);
	}
	
	if(g_iCvarListSize) {
		set_task(INPUT_DELAY + random_float(1.5, 3.5), "init_cvar_check", id + TASK_CVAR_CHECK);
	}
	
	get_user_authid(id, player_authid[id], charsmax(player_authid[]));
}
public client_disconnect(id)
{
	remove_task(id + TASK_CMD_CHECK);
	remove_task(id + TASK_FIRST_CMD);
	remove_task(id + TASK_CVAR_ANSWER);
	remove_task(id + TASK_CVAR_CHECK);
}
public init_cmd_check(id)
{
	id -= TASK_CMD_CHECK;
	
	first_check[id] = true;
	current_cmd_state[id] = -1;
	client_answered[id] = true;
	client_cmd_warnings[id] = 0;
	
	generate_string(rnd_str[id], charsmax(rnd_str[]));
	client_cmd(id, rnd_str[id]);
	set_task(FIRST_ANSWER_MAX_TIME, "check_first_cmd", id + TASK_FIRST_CMD);
}
public check_first_cmd(id)
{
	// client without answer
	id -= TASK_FIRST_CMD;
	
	if(++client_answer_check[id] >= FIRST_CMD_RECHECKS) {
		punishment(id, PUNISH_BAD_CLIENT);
	} else {
		init_cmd_check(id + TASK_CMD_CHECK);
	}
}
public client_command(id)
{
	new cmd[64]; read_argv(0, cmd, charsmax(cmd));

	if(current_cmd_state[id] >= 0 && equal(cmd, current_cmd[id])) {
		client_answered[id] = true;
		return PLUGIN_HANDLED;
	}
	
	if(g_iSlowhackAnswerSize && !client_answered[id] && TrieKeyExists(g_tSlowhackAnswer, cmd)) {
		// slowhack answer
		client_answered[id] = true;
		return PLUGIN_HANDLED;
	}
	
	if(equal(rnd_str[id], cmd)) {
		if(first_check[id]) {
			first_check[id] = false;
			remove_task(id + TASK_FIRST_CMD);
		}
		// send next cmd
		if(client_answered[id]) {
			client_answered[id] = false;
			
			if(++current_cmd_state[id] >= g_iCmdListSize) {
				set_task(RECHECK_DELAY + random_float(0.0, 30.0), "init_cmd_check", id + TASK_CMD_CHECK);
				return PLUGIN_HANDLED;
			}
			// add delay if too match cmds
			// 50-100 cmds for one cycle
			if(current_cmd_state[id] && !(current_cmd_state[id] % MAX_CMDS_FOR_LOOP)) {
				set_task(LOOP_DELAY, "send_next_cmd", id);
				return PLUGIN_HANDLED;
			}
		} else {
			if(++client_cmd_warnings[id] >= MAX_CMD_WARNINGS) {
				punishment(id, PUNISH_WRONG_CMD);
				return PLUGIN_HANDLED;
			}
		}
		send_next_cmd(id);
		return PLUGIN_HANDLED;
	}
	
	if(g_iBadCmdListSize) {
		new bad_cmd_info[BadCmdStruct];
		new result;
		
		new cmd_len = strlen(cmd), bad_cmd_len;
		
		for(new i; i < g_iBadCmdListSize; i++) {
			ArrayGetArray(g_aBadCmdList, i, bad_cmd_info);
			
			result = containi(cmd, bad_cmd_info[_BadCmd]);
			
			if(result == -1) {
				continue;
			}
			
			current_bad_cmd[id] = i;
			bad_cmd_len = strlen(bad_cmd_info[_BadCmd]);
			
			// log_amx("[ACC] found bad cmd: %s, pattern: %s. STEAM: %s", cmd, bad_cmd_info[_BadCmd], player_authid[id]);
			// punishment(id, PUNISH_BAD_CMD);
			
			if(!result && cmd_len > bad_cmd_len && bad_cmd_info[_BadCmdFlags] & BADCMD_PREFIX) {
				log_amx("[ACC] found prefix bad cmd: ^"%s^", pattern: ^"%s^". STEAM: %s", cmd, bad_cmd_info[_BadCmd], player_authid[id]);
				punishment(id, PUNISH_BAD_CMD);
				return PLUGIN_HANDLED;
			} else if(cmd_len - result == bad_cmd_len && cmd_len > bad_cmd_len  && bad_cmd_info[_BadCmdFlags] & BADCMD_SUFFIX) {
				log_amx("[ACC] found suffix bad cmd: ^"%s^", pattern: ^"%s^". STEAM: %s", cmd, bad_cmd_info[_BadCmd], player_authid[id]);
				punishment(id, PUNISH_BAD_CMD);
				return PLUGIN_HANDLED;
			} else if(bad_cmd_info[_BadCmdFlags] & BADCMD_ANY) {
				log_amx("[ACC] found bad cmd: ^"%s^", pattern: ^"%s^". STEAM: %s", cmd, bad_cmd_info[_BadCmd], player_authid[id]);
				punishment(id, PUNISH_BAD_CMD);
				return PLUGIN_HANDLED;
			}
		}
	}
	
	#if defined COMMAND_LOGGER
	if(!TrieKeyExists(g_tCmdLog, cmd)) {
		add_new_cmd(id, cmd);
	}
	#endif // COMMAND_LOGGER
	
	return PLUGIN_CONTINUE;
}
public send_next_cmd(id)
{
	new cmd_info[CommandStruct]; ArrayGetArray(g_aCmdList, current_cmd_state[id], cmd_info);
	copy(current_cmd[id], charsmax(current_cmd[]), cmd_info[_Cmd]);
	
	if(is_player_steam[id])
		send_director_cmd(id, current_cmd[id]);
	else
		client_cmd(id, current_cmd[id]);
	
	client_cmd(id, rnd_str[id]);
}


public init_cvar_check(id)
{
	id -= TASK_CVAR_CHECK;

	current_cvar_state[id] = 0;
	client_cvar_warnings[id] = 0;
	
	send_next_cvar(id);
}

public send_next_cvar(id)
{
	new cvar_info[CvarStruct]; ArrayGetArray(g_aCvarList, current_cvar_state[id], cvar_info);
	query_client_cvar(id, cvar_info[_Cvar], "cvar_callback", 1, _:cvar_info[_CvarFlags]);
	set_task(CVAR_ANSWER_TIME, "cvar_answer", id + TASK_CVAR_ANSWER);
}

public cvar_answer(id)
{
	id -= TASK_CVAR_ANSWER;
	
	if(++client_cvar_warnings[id] >= CVAR_ANSWER_RECHECKS) {
		punishment(id, PUNISH_BLOCK_CVAR_ANSWER);
	} else {
		send_next_cvar(id);
	}
}

public cvar_callback(id, cvar[], value[], params[])
{
	remove_task(id + TASK_CVAR_ANSWER);
	
	new CvarFlags:flags = CvarFlags:params[0];
	
	if(flags & (CVAR_EXIST|CVAR_NOT_EXIST)) {
		new eq = equal(value, "Bad CVAR request");
		if(!eq && flags & CVAR_EXIST) {
			// punish for exist cvar
			log_amx("[ACC] found bad cvar: %s. STEAM: %s", cvar, player_authid[id]);
			punishment(id, PUNISH_WRONG_CVAR);
			return PLUGIN_HANDLED;
		}
		if(eq && flags & CVAR_NOT_EXIST) {
			// punish for not exist cvar
			log_amx("[ACC] where is your cvar: %s. STEAM: %s", cvar, player_authid[id]);
			punishment(id, PUNISH_WRONG_CVAR);
			return PLUGIN_HANDLED;
		}
	}

	if(current_cvar_state[id] >= ArraySize(g_aCvarList)) {
		log_amx("[ACC] Undefined behavior. Cvar: %s, value: %s, flags: %d", cvar, value, flags);
		return PLUGIN_HANDLED;
	}

	new cvar_info[CvarStruct]; ArrayGetArray(g_aCvarList, current_cvar_state[id], cvar_info);
	
	if(flags & (CVAR_EQUAL|CVAR_NOT_EQUAL)) {
		if((equali(value, cvar_info[_CvarValue]) || str_to_float(value) == str_to_float(cvar_info[_CvarValue])) && flags & CVAR_EQUAL) {
			log_amx("[ACC] found equal cvar value: %s %s == %s. STEAM: %s", cvar, value, cvar_info[_CvarValue], player_authid[id]);
			punishment(id, PUNISH_WRONG_CVAR);
			return PLUGIN_HANDLED;
		} else if(flags & CVAR_NOT_EQUAL) {
			log_amx("[ACC] found not equal cvar value: %s %s != %s. STEAM: %s", cvar, value, cvar_info[_CvarValue], player_authid[id]);
			punishment(id, PUNISH_WRONG_CVAR);
			return PLUGIN_HANDLED;
		}
	}
	
	if(flags & CVAR_ABOVE && str_to_float(value) > cvar_info[_CvarValueAbove]) {
		log_amx("[ACC] found cvar value: %s %s > %.1f. STEAM: %s", cvar, value, cvar_info[_CvarValueAbove], player_authid[id]);
		punishment(id, PUNISH_WRONG_CVAR);
		return PLUGIN_HANDLED;
	}
	
	if(flags & CVAR_BELOW && str_to_float(value) < cvar_info[_CvarValueBelow]) {
		log_amx("[ACC] found cvar value: %s %s < %.1f. STEAM: %s", cvar, value, cvar_info[_CvarValueBelow], player_authid[id]);
		punishment(id, PUNISH_WRONG_CVAR);
		return PLUGIN_HANDLED;
	}
	
	if(++current_cvar_state[id] >= g_iCvarListSize) {
		set_task(RECHECK_DELAY, "init_cvar_check", id + TASK_CVAR_CHECK);
		return PLUGIN_HANDLED;
	}
	send_next_cvar(id);
	
	return PLUGIN_HANDLED;
}

#if defined COMMAND_LOGGER
add_new_cmd(id, cmd[])
{
	TrieSetCell(g_tCmdLog, cmd, 1);
	new ip[32]; get_user_ip(id, ip, charsmax(ip), 1); // TODO: cache this
	new name[32]; get_user_name(id, name, charsmax(name));
	new text[256];
	formatex(text, charsmax(text), "// cmd: ^"%s^", player: %s, steamid: %s, ip: %s^nacc_add_cmd_log ^"%s^"", cmd, name, player_authid[id], ip, cmd);
	write_file(g_szCmdLogPath, text);
}
#endif // COMMAND_LOGGER

punishment(id, PunishType:type)
{
	// ban, kick, etc...
	new punish_index, reason[32];
	
	switch(type) {
		case PUNISH_BAD_CLIENT: {
			// bad client, protector
			log_amx("[ACC] found bad client or protector. STEAMID: %s", player_authid[id]);
			
			#if defined KICK_BAD_CLIENT
			server_cmd("kick #%d Bad Client", get_user_userid(id));
			#endif
			
			return;
		}
		case PUNISH_BLOCK_CVAR_ANSWER: {
			new cvar_info[CvarStruct]; ArrayGetArray(g_aCvarList, current_cvar_state[id], cvar_info);
			log_amx("[ACC] cvar without answer: %s. STEAM: %s", cvar_info[_Cvar], player_authid[id]);
		
			#if defined KICK_FOR_BLOCK_CVAR_ANSWER
			server_cmd("kick #%d Block Cvar", get_user_userid(id));
			#endif
			
			return;
		}
		case PUNISH_WRONG_CMD: {
			log_amx("[ACC] found wrong cmd. STEAMID: %s, cmd: ^"%s^".", player_authid[id], current_cmd[id]);
			
			new cmd_info[CommandStruct]; ArrayGetArray(g_aCmdList, current_cmd_state[id], cmd_info);
			punish_index = get_punish_index(cmd_info[_CmdPunishLevel]);
			
			if(punish_index == INVALID_INDEX) {
				log_amx("[ACC] Can't find ^"%d^" punish level for ^"%s^".", cmd_info[_CmdPunishLevel], cmd_info[_Cmd]);
				return;
			}
			
			copy(reason, charsmax(reason), cmd_info[_Cmd]);
		}
		case PUNISH_WRONG_CVAR: {
			new cvar_info[CvarStruct]; ArrayGetArray(g_aCvarList, current_cvar_state[id], cvar_info);
			punish_index = get_punish_index(cvar_info[_CvarPunishLevel]);
			
			if(punish_index == INVALID_INDEX) {
				log_amx("[ACC] Can't find ^"%d^" punish level for ^"%s^".", cvar_info[_CvarPunishLevel], cvar_info[_Cvar]);
				return;
			}
			
			copy(reason, charsmax(reason), cvar_info[_Cvar]);
		}
		case PUNISH_BAD_CMD: {
			new bad_cmd_info[BadCmdStruct]; ArrayGetArray(g_aBadCmdList, current_bad_cmd[id], bad_cmd_info);
			punish_index = get_punish_index(bad_cmd_info[_BadCmdPunishLevel]);
			
			if(punish_index == INVALID_INDEX) {
				log_amx("[ACC] Can't find ^"%d^" punish level for ^"%s^".", bad_cmd_info[_BadCmdPunishLevel], bad_cmd_info[_BadCmd]);
				return;
			}
			
			copy(reason, charsmax(reason), bad_cmd_info[_BadCmd]);
		}
	}
	
	new punish_info[PunishStruct]; ArrayGetArray(g_aPunishList, punish_index, punish_info);
	new userid[16]; num_to_str(get_user_userid(id), userid, charsmax(userid));
	
	replace(punish_info[_PunishCmd], charsmax(punish_info[_PunishCmd]), "%userid%", userid);
	replace(punish_info[_PunishCmd], charsmax(punish_info[_PunishCmd]), "%reason%", reason);
	
	server_cmd("%s", punish_info[_PunishCmd]);
}
generate_string(str[], len)
{
	for(new i; i < len; i++) {
		switch(random(2)) {
			case 0: str[i] = random_num('A', 'Z');
			case 1: str[i] = random_num('a', 'z');
		}
	}
	str[len] = 0;
}
get_punish_index(level)
{
	new size = ArraySize(g_aPunishList);
	for(new i, punish_info[PunishStruct]; i < size; i++) {
		ArrayGetArray(g_aPunishList, i, punish_info);
		if(level == punish_info[_PunishLevel]) {
			return i;
		}
	}
	return INVALID_INDEX;
}

stock send_director_cmd(id , text[])
{
	message_begin( MSG_ONE, SVC_DIRECTOR, _, id );
	write_byte( strlen(text) + 2 );
	write_byte( 10 );
	write_string( text );
	message_end();
}

stock bool:is_user_steam(id)
{
	static dp_pointer;
	if(dp_pointer || (dp_pointer = get_cvar_pointer("dp_r_id_provider"))) {
		server_cmd("dp_clientinfo %d", id); server_exec();
		return (get_pcvar_num(dp_pointer) == 2) ? true : false;
	}
	return false;
}
