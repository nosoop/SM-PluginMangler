/**
 * [ANY] Plugin Mangler
 * 
 * Allows server administrators to manage plugins in batches, as well as move plugins to / from
 * the disabled directory.
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <stocksoup/plugin_utils>
#include <stocksoup/log_server>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[ANY] Plugin Mangler",
	author = "nosoop",
	description = "Load, unload, reload, enable, and disable multiple plugins in one go.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-PluginMangler"
}

enum PluginAction {
	Action_Invalid = 0,
	Action_Load,
	Action_Reload,
	Action_Unload,
	Action_Enable,
	Action_Disable,
	Action_Find,
	Action_Info
};

char g_ActionCommands[][] = {
	"", "load", "reload", "unload", "enable", "disable", "find", "info"
};

public void OnPluginStart() {
	// EnableDisable.smx conflicts with this plugin's `plugins` server command
	if (DisablePluginFile("EnableDisable")) {
		LogServer("EnableDisable conflicts with this plugin's commands. "
				... "It has been unloaded and moved to the 'disabled/' directory.");
	}
	
	RegAdminCmd("sm_plugins", AdminCmd_PluginManage, ADMFLAG_ROOT);
	
	RegServerCmd("plugins", ServerCmd_PluginManage);
}

public Action AdminCmd_PluginManage(int client, int argc) {
	PluginAction action;
	if (argc > 0) {
		char actionName[16];
		GetCmdArg(1, actionName, sizeof(actionName));
		
		for (int i = 0; i < view_as<int>(PluginAction); i++) {
			if (strlen(actionName) > 0 && StrEqual(actionName, g_ActionCommands[i])) {
				action = view_as<PluginAction>(i);
			}
		}
	} else {
		char command[64];
		GetCmdArg(0, command, sizeof(command));
		ReplyToCommand(client, "Usage: %s [action] [plugin, ...]", command);
	}
	
	// TODO get all plugin filenames and treat them as expressions to be expanded?
	
	char pluginName[PLATFORM_MAX_PATH];
	for (int i = 1; i < argc; i++) {
		// off by one, command name at arg 0
		GetCmdArg(i + 1, pluginName, sizeof(pluginName));
		
		// append .smx if necessary for ReplyToCommand messages
		int ext = FindCharInString(pluginName, '.', true);
		if (ext == -1 || StrContains(pluginName[ext], ".smx", false) != 0) {
			StrCat(pluginName, sizeof(pluginName), ".smx");
		}
		
		switch (action) {
			case Action_Load: {
				LoadPluginFile(pluginName);
			}
			case Action_Reload: {
				ReloadPluginFile(pluginName);
			}
			case Action_Unload: {
				UnloadPluginFile(pluginName);
			}
			case Action_Enable: {
				if (EnablePluginFile(pluginName)) {
					ReplyToCommand(client,
							"[SM] Plugin %s has been moved out of the 'disabled/' directory.",
							pluginName);
				}
			}
			case Action_Disable: {
				if (DisablePluginFile(pluginName)) {
					ReplyToCommand(client,
							"[SM] Plugin %s has been moved to the 'disabled/' directory.",
							pluginName);
				}
			}
			case Action_Info: {
				if (!PerformPluginCommand("info", pluginName)) {
					ReplyToCommand(client, "[SM] Plugin %s is not loaded.", pluginName);
				}
			}
			case Action_Find: {
				// TODO treat argument as regex and iterate plugin filenames?
			}
		}
	}
	return Plugin_Handled;
}

public Action ServerCmd_PluginManage(int argc) {
	return AdminCmd_PluginManage(0, argc);
}