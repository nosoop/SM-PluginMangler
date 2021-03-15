/**
 * [ANY] Plugin Mangler
 * 
 * Allows server administrators to manage plugins in batches, as well as move plugins to / from
 * the disabled directory.
 */
#pragma semicolon 1
#include <sourcemod>

#include <regex>

#pragma newdecls required
#include <stocksoup/plugin_utils>
#include <stocksoup/log_server>

#define PLUGIN_VERSION "1.3.0"
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
	Action_Info,
	Action_RefreshStale,
	Action_ListDuplicates,
	NUM_PLUGIN_ACTIONS,
};

char g_ActionCommands[][] = {
	"", "load", "reload", "unload", "enable", "disable", "find", "info", "refresh_stale",
	"list_duplicates"
};

char g_ActionInfo[][] = {
	"",
	"Load a plugin",
	"Reloads a plugin",
	"Unload a plugin",
	"Moves a plugin out of 'disabled/' and loads it",
	"Unloads a plugin and moves it to 'disabled/'",
	"Finds plugins matching the regular expression (TODO)",
	"Information about a plugin",
	"Reloads recently installed plugins",
	"Displays a list of enabled plugins with a matching base name"
};

int g_LastRefresh;

StringMap g_FuturePluginTimes;

Regex g_ExpressionArg;

public void OnPluginStart() {
	// EnableDisable.smx conflicts with this plugin's `plugins` server command
	if (DisablePluginFile("EnableDisable")) {
		LogServer("EnableDisable conflicts with this plugin's commands. "
				... "It has been unloaded and moved to the 'disabled/' directory.");
	}
	
	RegAdminCmd("sm_plugins", AdminCmd_PluginManage, ADMFLAG_ROOT);
	RegAdminCmd("plugins", AdminCmd_PluginManage, ADMFLAG_ROOT);
	
	g_FuturePluginTimes = new StringMap();
	
	g_ExpressionArg = new Regex("^\\/(.*)\\/$");
}

public void OnMapStart() {
	g_LastRefresh = GetTime();
	
	/**
	 * Store times of plugins with mtimes newer than system clock.
	 * 
	 * Keeping track of this means that plugins with mtime newer than clock only get reloaded
	 * when their mtime changes.
	 */
	
	// We can't remove individual items from the StringMap, so we'll have to rebuild it.
	g_FuturePluginTimes.Clear();
	
	Handle iterator = GetPluginIterator();
	while (MorePlugins(iterator)) {
		Handle plugin = ReadPlugin(iterator);
		
		char pluginName[PLATFORM_MAX_PATH], pluginPath[PLATFORM_MAX_PATH];
		
		GetPluginFilename(plugin, pluginName, sizeof(pluginName));
		BuildPath(Path_SM, pluginPath, sizeof(pluginPath), "plugins/%s", pluginName);
		
		int mtime = GetFileTime(pluginPath, FileTime_LastChange);
		
		if (mtime > g_LastRefresh) {
			g_FuturePluginTimes.SetValue(pluginName, mtime, false);
		}
	}
	delete iterator;
}

public Action AdminCmd_PluginManage(int client, int argc) {
	PluginAction action = Action_Invalid;
	if (argc > 0) {
		char actionName[16];
		GetCmdArg(1, actionName, sizeof(actionName));
		
		for (PluginAction i; i < NUM_PLUGIN_ACTIONS; i++) {
			if (strlen(actionName) > 0 && StrEqual(actionName, g_ActionCommands[i])) {
				action = i;
			}
		}
		
		if (action == Action_Invalid) {
			ReplyToCommand(client, "[SM] Unknown plugin management command '%s'", actionName);
		}
	} else {
		char command[64];
		GetCmdArg(0, command, sizeof(command));
		
		if (client && GetCmdReplySource() == SM_REPLY_TO_CHAT) {
			ReplyToCommand(client, "[SM] See console output for usage instructions.");
			SetCmdReplySource(SM_REPLY_TO_CONSOLE);
		}
		
		ReplyToCommand(client, "Usage: %s [action] [plugin, ...]", command);
		
		for (int i = 1; i < view_as<int>(PluginAction); i++) {
			ReplyToCommand(client, "    %-16s - %s", g_ActionCommands[i], g_ActionInfo[i]);
		}
	}
	
	bool bSinglePluginAction;
	
	// Perform actions that do not need plugin names passed in.
	switch (action) {
		case Action_RefreshStale: {
			int nReloads;
			bool selfStale;
			char pluginSelfName[PLATFORM_MAX_PATH];
			GetPluginFilename(INVALID_HANDLE, pluginSelfName, sizeof(pluginSelfName));
			
			Handle iterator = GetPluginIterator();
			while (MorePlugins(iterator)) {
				Handle plugin = ReadPlugin(iterator);
				
				char pluginName[PLATFORM_MAX_PATH];
				GetPluginFilename(plugin, pluginName, sizeof(pluginName));
				
				int mtime;
				if (IsPluginStale(pluginName, mtime)) {
					if (StrEqual(pluginName, pluginSelfName)) {
						if (!selfStale) {
							nReloads++;
						}
						
						// Should not reload self while processing other plugins
						selfStale = true;
					} else {
						nReloads++;
						ReloadPlugin(plugin);
					}
					
					// Plugin is now from the future, store time
					if (mtime > GetTime()) {
						g_FuturePluginTimes.SetValue(pluginName, mtime);
					}
				}
			}
			delete iterator;
			
			// Print the number of plugins reloaded so 0 reloads still provides a response
			ReplyToCommand(client, "[SM] %d stale plugin(s) have been found and reloaded.",
					nReloads);
			
			if (selfStale) {
				ReloadPlugin();
			}
			
			g_LastRefresh = GetTime();
		}
		case Action_ListDuplicates: {
			/**
			 * Outputs a list of plugins that share the same base name.
			 * Useful if you forgot you had a specific plugin in another directory already.
			 */
			StringMap pluginCounts = new StringMap();
			
			Handle iterator = GetPluginIterator();
			while (MorePlugins(iterator)) {
				Handle plugin = ReadPlugin(iterator);
				
				char pluginName[PLATFORM_MAX_PATH];
				GetPluginFilename(plugin, pluginName, sizeof(pluginName));
				
				char pluginBaseName[PLATFORM_MAX_PATH];
				strcopy(pluginBaseName, sizeof(pluginBaseName),
						pluginName[ FindCharInString(pluginName, '/') + 1]);
				
				int nInstances;
				pluginCounts.GetValue(pluginBaseName, nInstances);
				pluginCounts.SetValue(pluginBaseName, ++nInstances);
			}
			delete iterator;
			
			int nReportedDuplicates;
			StringMapSnapshot uniquePluginNames = pluginCounts.Snapshot();
			for (int i = 0; i < uniquePluginNames.Length; i++) {
				char pluginBaseName[PLATFORM_MAX_PATH];
				uniquePluginNames.GetKey(i, pluginBaseName, sizeof(pluginBaseName));
				
				int nInstances;
				pluginCounts.GetValue(pluginBaseName, nInstances);
				
				if (nInstances > 1) {
					ReplyToCommand(client, "%d active plugins have the base name '%s'",
							nInstances, pluginBaseName);
					nReportedDuplicates++;
				}
			}
			delete uniquePluginNames;
			delete pluginCounts;
			
			if (!nReportedDuplicates) {
				ReplyToCommand(client, "No duplicate plugins found.");
			}
		}
		default: {
			bSinglePluginAction = true;
		}
	}
	
	if (!bSinglePluginAction) {
		// was multi-plugin action that was performed above
		return Plugin_Handled;
	}
	
	ArrayList plugins = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	for (int i = 1; i < argc; i++) {
		// off by one, command name at arg 0
		char pluginName[PLATFORM_MAX_PATH];
		GetCmdArg(i + 1, pluginName, sizeof(pluginName));
		
		if (g_ExpressionArg.Match(pluginName)) {
			// argument is a regex of the form /{expr}/
			char regexArg[256];
			g_ExpressionArg.GetSubString(1, regexArg, sizeof(regexArg));
			
			RegexError regexError;
			char regexErrorString[256];
			Regex pluginRegex = new Regex(regexArg, _, regexErrorString,
					sizeof(regexErrorString), regexError);
			
			if (!regexError) {
				if (action == Action_Enable) {
					// match filenames of disabled plugins
					char pluginBasePath[PLATFORM_MAX_PATH];
					BuildPath(Path_SM, pluginBasePath, sizeof(pluginBasePath),
							"plugins/disabled/");
					
					ArrayStack directories =
							new ArrayStack(ByteCountToCells(PLATFORM_MAX_PATH));
					
					directories.PushString(pluginBasePath);
					
					// depth-first search
					char filePath[PLATFORM_MAX_PATH];
					char searchPath[PLATFORM_MAX_PATH];
					while (!directories.Empty) {
						/**
						 * get the next directory path to search
						 * 
						 * workaround since we can't get the current directory name off a
						 * DirectoryListing handle
						 */
						directories.PopString(searchPath, sizeof(searchPath));
						
						DirectoryListing dl = OpenDirectory(searchPath, false);
						FileType type;
						
						while (dl.GetNext(filePath, sizeof(filePath), type)) {
							switch (type) {
								case FileType_File: {
									char pluginFile[PLATFORM_MAX_PATH];
									
									// get filename relative to plugins/disabled
									Format(pluginFile, sizeof(pluginFile), "%s%s",
											searchPath[strlen(pluginBasePath)], filePath);
									
									if (plugins.FindString(pluginFile) == -1
											&& pluginRegex.Match(pluginFile)) {
										plugins.PushString(pluginFile);
										
										LogServer("Found matching plugin %s", pluginFile);
									}
								}
								case FileType_Directory: {
									if (!StrEqual(filePath, "..") && !StrEqual(filePath, ".")) {
										char nextPath[PLATFORM_MAX_PATH];
										Format(nextPath, sizeof(nextPath), "%s%s/",
												searchPath, filePath);
										
										// push directory name onto the stack
										directories.PushString(nextPath);
									}
								}
							}
						}
						
						delete dl;
					}
					delete directories;
				} else {
					// match filenames of currently running plugins
					Handle iterator = GetPluginIterator();
					while (MorePlugins(iterator)) {
						char iterPluginName[PLATFORM_MAX_PATH];
						GetPluginFilename(ReadPlugin(iterator), iterPluginName,
								sizeof(iterPluginName));
						
						if (plugins.FindString(iterPluginName) == -1
								&& pluginRegex.Match(iterPluginName)) {
							plugins.PushString(iterPluginName);
							
							LogServer("Found matching plugin %s", iterPluginName);
						}
					}
					delete iterator;
				}
				delete pluginRegex;
			} else {
				LogError("Error while compiling '%s': %s", regexArg, regexErrorString);
			}
		} else {
			// not a regular expression; assume it's a plugin file and add to the list
			plugins.PushString(pluginName);
		}
	}
	
	char pluginName[PLATFORM_MAX_PATH];
	for (int i = 0; i < plugins.Length; i++) {
		plugins.GetString(i, pluginName, sizeof(pluginName));
		
		// append .smx if necessary for ReplyToCommand messages
		int ext = FindCharInString(pluginName, '.', true);
		if (ext == -1 || StrContains(pluginName[ext], ".smx", false) != 0) {
			StrCat(pluginName, sizeof(pluginName), ".smx");
		}
		
		switch (action) {
			case Action_Load: {
				if (!LoadPluginFile(pluginName)) {
					ReplyToCommand(client,
							"[SM] Plugin %s failed to load: Unable to open file.", pluginName);
				}
			}
			case Action_Reload: {
				if (!ReloadPluginFile(pluginName)) {
					ReplyToCommand(client, "[SM] Plugin %s is not loaded.", pluginName);
				} else if (client) {
					ReplyToCommand(client, "[SM] Plugin %s reloaded successfully.", pluginName);
				}
			}
			case Action_Unload: {
				if (!UnloadPluginFile(pluginName)) {
					ReplyToCommand(client, "[SM] Plugin %s is not loaded.", pluginName);
				} else if (client) {
					ReplyToCommand(client, "[SM] Plugin %s unloaded successfully.", pluginName);
				}
			}
			case Action_Enable: {
				if (EnablePluginFile(pluginName)) {
					ReplyToCommand(client,
							"[SM] Plugin %s has been moved out of the 'disabled/' directory.",
							pluginName);
				} else {
					ReplyToCommand(client,
							"[SM] Plugin %s failed to load: Unable to open file.", pluginName);
				}
			}
			case Action_Disable: {
				if (DisablePluginFile(pluginName)) {
					ReplyToCommand(client,
							"[SM] Plugin %s has been moved to the 'disabled/' directory.",
							pluginName);
				} else {
					ReplyToCommand(client, "[SM] Plugin %s is not loaded.", pluginName);
				}
			}
			case Action_Info: {
				if (!PerformPluginCommand("info", pluginName)) {
					ReplyToCommand(client, "[SM] Plugin %s is not loaded.", pluginName);
				}
			}
			case Action_Find: {
				// TODO treat argument as regex and iterate plugin filenames?
				ReplyToCommand(client,
						"[SM] The 'find' subcommand has not been implemented yet.");
			}
		}
	}
	delete plugins;
	return Plugin_Handled;
}

bool IsPluginStale(const char[] pluginName, int &mtime) {
	char pluginPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, pluginPath, sizeof(pluginPath), "plugins/%s", pluginName);
	
	mtime = GetFileTime(pluginPath, FileTime_LastChange);
	int existingTime;
	
	if (g_FuturePluginTimes.GetValue(pluginName, existingTime)) {
		// If plugin is from the future, check if newer than last known mtime
		return (mtime > existingTime);
	}
	
	// otherwise just check that it's newer than the last full refresh
	return (mtime > g_LastRefresh);
}
