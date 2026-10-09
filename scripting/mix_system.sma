/*
 * GAMELAND Competitive 5v5 Mix System
 * Refactored & ReAPI Modernized Edition
 * Author: GAMELAND Team
 * Contact: l1gameland@gmail.com
 *
 * Features:
 * - 100% Pure ReAPI (Zero fun/cstrike, high performance, ReGameDLL native)
 * - Purged SQL / Database / Points / Rank clutter (Zero lag / zero MySQL dependencies)
 * - Warmup / DM1 Mode (/dm1 & /warm): $16,000 spawn money, normal practice rounds, clean team wipe reset
 * - Zero HLTV or Client Demo recording
 * - Fixed Double Round Score Count Bug (Protected by g_bRoundScored atomic flag)
 * - Fixed Halftime Team Swap Bug (Atomic rg_swap_all_players & score swap)
 * - Fixed Knife Round Restarts & Side Vote race condition
 * - Admin /mix Global Vote: Option 1: Knife Round | Option 2: Direct Live Match
 * - Professional /a Master Admin Menu:
 *     1. Admin Manager (Add Admin with presets/flags directly to users.ini + auto reload)
 *     2. Match / Mix Control (Vote Start, Direct Live, Knife, Warmup, Pause)
 *     3. Team Control (Swap Teams, Move CT/TR/SPEC, Spec All)
 *     4. Server Control (Restart 1s, Alltalk ON/OFF, Chat Mute, Password)
 *     5. Map & Moderation shortcuts (Kick, Ban, Slap, Maps)
 * - Full backward-compatible natives & forwards for external plugins
 */

#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <mix_system>

#define PLUGIN_NAME        "GAMELAND Mix System"
#define PLUGIN_VERSION     "2.1.0-ReAPI"
#define PLUGIN_AUTHOR      "GAMELAND"

// -----------------------------------------------------------------------------
// Constants & Enums
// -----------------------------------------------------------------------------
enum MatchState
{
    STATE_WARMUP = 0,
    STATE_KNIFE,
    STATE_FIRST_HALF,
    STATE_SECOND_HALF,
    STATE_OVERTIME_FIRST_HALF,
    STATE_OVERTIME_SECOND_HALF
}

enum TeamScore
{
    CT_SCORE = 0,
    TERO_SCORE
}

#define TASK_HALFTIME_LIVE       3101
#define TASK_KNIFE_COUNTDOWN     3102
#define TASK_LIVE_COUNTDOWN      3103
#define TASK_HUD_STATUS          3104
#define TASK_TIMEOUT_EXPIRE      3105
#define TASK_END_ROUND           3106
#define TASK_MATCH_END           3107
#define TASK_KNIFE_VOTE          3108
#define TASK_MIX_VOTE            3109

#define VOTE_STAY   1
#define VOTE_SWITCH 2

// -----------------------------------------------------------------------------
// Admin Manager Data Structure
// -----------------------------------------------------------------------------
enum AdminAddSession
{
    SessionTargetId,
    SessionAuth[64],
    SessionName[32],
    SessionFlags[36],
    SessionAccountFlags[8],
    SessionPassword[32]
}

new g_eAdminSession[MAX_PLAYERS + 1][AdminAddSession]

// -----------------------------------------------------------------------------
// Global Variables
// -----------------------------------------------------------------------------
new MatchState:g_iMatchState = STATE_WARMUP

new g_iScore[TeamScore]
new g_iFirstHalfScore[TeamScore]
new g_iOvertimeScore[TeamScore]

new bool:g_bRoundScored = false
new bool:g_bChatMuted = false
new bool:g_bPaused = false
new g_iPauseTimer = 0
new bool:g_bTeamTimeoutUsed[TeamScore]

// Settings from MixSettings.ini
new g_szChatPrefix[32] = "[MIX]"
new g_iOvertimeRounds = 3
new g_iOvertimeTriggerScore = 15
new g_iMixEndRound = 16
new g_szAdminFlags[16] = "c"
new g_szAdminAccess[16] = "c"
new g_iFreezeTimeSwap = 10
new bool:g_bAutoOvertime = true
new g_szStartConfig[64] = "start.cfg"
new g_szStopConfig[64] = "stop.cfg"
new g_iKnifeDelay = 10
new g_iWarmMoney = 16000
new bool:g_bForceWarmup = true
new g_iPauseDuration = 60

// Player data
new g_szUserName[MAX_PLAYERS + 1][MAX_NAME_LENGTH]

// /mix Global Vote (Knife vs Direct Live)
new g_iMixVoteKnife = 0
new g_iMixVoteLive = 0
new bool:g_bPlayerVotedMix[MAX_PLAYERS + 1]
new g_iMixVoteTimer = 0

// Knife round side selection vote
new TeamName:g_iKnifeWinnerTeam = TEAM_UNASSIGNED
new g_iVoteStay = 0
new g_iVoteSwitch = 0
new bool:g_bPlayerVoted[MAX_PLAYERS + 1]
new g_iKnifeVoteTimer = 0

// Countdown
new g_iLiveCountdown = 3
new g_iMatchStartTime = 0

// HUD Sync
new g_iHudSync

// Forwards
new g_hFwdPlayerKilled
new g_hFwdGameBeginPre
new g_hFwdGameBeginPost
new g_hFwdNewRound
new g_hFwdGameStopped
new g_hFwdGameOver
new g_hFwdMatchWinner
new g_hFwdUserSave
new g_hFwdDbConnected
new g_hFwdSysLeaver
new g_iRet

// Command dynamic arrays
new Array:g_aStartCmds
new Array:g_aStopCmds
new Array:g_aWarmCmds
new Array:g_aKnifeCmds
new Array:g_aChatOnCmds
new Array:g_aChatOffCmds
new Array:g_aOvertimeCmds
new Array:g_aPassOnCmds
new Array:g_aPassOffCmds
new Array:g_aSpecAllCmds
new Array:g_aRestartCmds
new Array:g_aScoreCmds
new Array:g_aMoveCTCmds
new Array:g_aMoveTCmds
new Array:g_aMoveSpecCmds
new Array:g_aPauseCmds

// -----------------------------------------------------------------------------
// Plugin Init & Configuration
// -----------------------------------------------------------------------------
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR)
    register_cvar("gameland_mix_version", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY)

    register_dictionary("mix_system.txt")

    // ReAPI HookChains
    RegisterHookChain(RG_CBasePlayer_Spawn, "RG_CBasePlayer_Spawn_Post", .post = true)
    RegisterHookChain(RG_CBasePlayer_Killed, "RG_CBasePlayer_Killed_Post", .post = true)
    RegisterHookChain(RG_RoundEnd, "RG_RoundEnd_Post", .post = true)
    RegisterHookChain(RG_CSGameRules_RestartRound, "RG_CSGameRules_RestartRound_Post", .post = true)

    // Dynamic arrays for commands
    InitCommandArrays()

    // Load configuration
    LoadConfiguration()

    // Create Forwards
    g_hFwdPlayerKilled = CreateMultiForward("mix_player_killed", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL, FP_STRING, FP_STRING)
    g_hFwdGameBeginPre = CreateMultiForward("mix_game_begin_pre", ET_IGNORE)
    g_hFwdGameBeginPost = CreateMultiForward("mix_game_begin_post", ET_IGNORE, FP_CELL, FP_CELL, FP_STRING, FP_STRING, FP_CELL)
    g_hFwdNewRound = CreateMultiForward("mix_game_new_round", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)
    g_hFwdGameStopped = CreateMultiForward("mix_game_stopped", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)
    g_hFwdGameOver = CreateMultiForward("mix_game_over", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL, FP_CELL)
    g_hFwdMatchWinner = CreateMultiForward("mix_match_winner", ET_IGNORE, FP_CELL)
    g_hFwdUserSave = CreateMultiForward("mix_user_save", ET_IGNORE, FP_CELL)
    g_hFwdDbConnected = CreateMultiForward("mix_database_connected", ET_IGNORE, FP_CELL, FP_CELL)
    g_hFwdSysLeaver = CreateMultiForward("mix_sys_leaver", ET_IGNORE, FP_STRING)

    // Execute initial dummy DB connected forward for third-party listeners
    ExecuteForward(g_hFwdDbConnected, g_iRet, 0, 0)

    g_iHudSync = CreateHudSyncObj()

    // Register HUD task
    set_task(1.0, "Task_HudDisplay", TASK_HUD_STATUS, .flags = "b")

    // Standard client commands fallback
    register_clcmd("say /comenzi", "Cmd_ShowCommands")
    register_clcmd("say_team /comenzi", "Cmd_ShowCommands")
    register_clcmd("say /live", "Cmd_DirectLive")
    register_clcmd("say_team /live", "Cmd_DirectLive")

    // Master /a Admin Menu commands
    register_clcmd("say /a", "Cmd_AdminDashboard")
    register_clcmd("say_team /a", "Cmd_AdminDashboard")
    register_clcmd("a", "Cmd_AdminDashboard")
    register_clcmd("amx_a", "Cmd_AdminDashboard")
    register_clcmd("say /adminmenu", "Cmd_AdminDashboard")
    register_clcmd("say_team /adminmenu", "Cmd_AdminDashboard")

    register_clcmd("say", "Hook_Say")
    register_clcmd("say_team", "Hook_SayTeam")

    // Start with Warmup if configured
    if(g_bForceWarmup)
    {
        StartWarmup()
    }
}

public plugin_natives()
{
    register_library("mix_system")

    register_native("Mix_IsHalf", "native_is_half")
    register_native("Mix_IsLastRound", "native_is_last_round")
    register_native("Mix_IsPreLastRound", "native_is_prelast_round")
    register_native("Mix_CanOvertime", "native_can_overtime")
    register_native("Mix_IsStarted", "native_is_started")
    register_native("Mix_IsWarm", "native_is_warm")
    register_native("Mix_GetPrefix", "native_get_prefix")
    register_native("Mix_GetUserName", "native_get_username")

    // Dummy backwards-compatible natives (Points & SQL removed)
    register_native("Mix_UserPoints", "native_user_points")
    register_native("Mix_HasPointsSys", "native_has_points_sys")
    register_native("Mix_SearchForUser", "native_search_for_user")
    register_native("Mix_MultiplyFactor", "native_multiply_factor")
    register_native("Mix_GetPointsTable", "native_get_points_table")
}

public plugin_end()
{
    DestroyCommandArrays()
}

// -----------------------------------------------------------------------------
// Command Arrays Management
// -----------------------------------------------------------------------------
InitCommandArrays()
{
    g_aStartCmds = ArrayCreate(32)
    g_aStopCmds = ArrayCreate(32)
    g_aWarmCmds = ArrayCreate(32)
    g_aKnifeCmds = ArrayCreate(32)
    g_aChatOnCmds = ArrayCreate(32)
    g_aChatOffCmds = ArrayCreate(32)
    g_aOvertimeCmds = ArrayCreate(32)
    g_aPassOnCmds = ArrayCreate(32)
    g_aPassOffCmds = ArrayCreate(32)
    g_aSpecAllCmds = ArrayCreate(32)
    g_aRestartCmds = ArrayCreate(32)
    g_aScoreCmds = ArrayCreate(32)
    g_aMoveCTCmds = ArrayCreate(32)
    g_aMoveTCmds = ArrayCreate(32)
    g_aMoveSpecCmds = ArrayCreate(32)
    g_aPauseCmds = ArrayCreate(32)
}

DestroyCommandArrays()
{
    ArrayDestroy(g_aStartCmds)
    ArrayDestroy(g_aStopCmds)
    ArrayDestroy(g_aWarmCmds)
    ArrayDestroy(g_aKnifeCmds)
    ArrayDestroy(g_aChatOnCmds)
    ArrayDestroy(g_aChatOffCmds)
    ArrayDestroy(g_aOvertimeCmds)
    ArrayDestroy(g_aPassOnCmds)
    ArrayDestroy(g_aPassOffCmds)
    ArrayDestroy(g_aSpecAllCmds)
    ArrayDestroy(g_aRestartCmds)
    ArrayDestroy(g_aScoreCmds)
    ArrayDestroy(g_aMoveCTCmds)
    ArrayDestroy(g_aMoveTCmds)
    ArrayDestroy(g_aMoveSpecCmds)
    ArrayDestroy(g_aPauseCmds)
}

// -----------------------------------------------------------------------------
// Configuration Parser
// -----------------------------------------------------------------------------
LoadConfiguration()
{
    new szConfigPath[128]
    get_configsdir(szConfigPath, charsmax(szConfigPath))
    add(szConfigPath, charsmax(szConfigPath), "/MixSettings.ini")

    if(!file_exists(szConfigPath))
    {
        server_print("[%s] Config file '%s' not found! Using defaults.", PLUGIN_NAME, szConfigPath)
        RegisterDefaultCommands()
        return
    }

    new iFile = fopen(szConfigPath, "rt")
    if(!iFile)
    {
        RegisterDefaultCommands()
        return
    }

    new szLine[256], szKey[64], szValue[192]
    new iSection = 0 // 1: General, 2: Commands, 3: Warm

    while(!feof(iFile))
    {
        fgets(iFile, szLine, charsmax(szLine))
        trim(szLine)

        if(!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue

        if(szLine[0] == '[')
        {
            if(containi(szLine, "General") != -1)
                iSection = 1
            else if(containi(szLine, "Commands") != -1)
                iSection = 2
            else if(containi(szLine, "Warm") != -1)
                iSection = 3
            else
                iSection = 0
            continue
        }

        strtok(szLine, szKey, charsmax(szKey), szValue, charsmax(szValue), '=')
        trim(szKey)
        trim(szValue)

        switch(iSection)
        {
            case 1: // General Settings
            {
                if(equal(szKey, "CHAT_PREFIX"))
                    copy(g_szChatPrefix, charsmax(g_szChatPrefix), szValue)
                else if(equal(szKey, "OVERTIME_ROUNDS"))
                    g_iOvertimeRounds = str_to_num(szValue)
                else if(equal(szKey, "OVERTIME_SCORE"))
                    g_iOvertimeTriggerScore = str_to_num(szValue)
                else if(equal(szKey, "MIX_END_ROUND"))
                    g_iMixEndRound = str_to_num(szValue)
                else if(equal(szKey, "ADMIN_CHAT_FLAGS"))
                    copy(g_szAdminFlags, charsmax(g_szAdminFlags), szValue)
                else if(equal(szKey, "ADMIN_LEVEL_ACCESS"))
                    copy(g_szAdminAccess, charsmax(g_szAdminAccess), szValue)
                else if(equal(szKey, "FREEZE_TIME_SWAP"))
                    g_iFreezeTimeSwap = str_to_num(szValue)
                else if(equal(szKey, "AUTOMATIC_OVERTIME"))
                    g_bAutoOvertime = bool:str_to_num(szValue)
                else if(equal(szKey, "START_CONFIG"))
                    copy(g_szStartConfig, charsmax(g_szStartConfig), szValue)
                else if(equal(szKey, "STOP_CONFIG"))
                    copy(g_szStopConfig, charsmax(g_szStopConfig), szValue)
                else if(equal(szKey, "KNIFE_ROUND_START_DELAY"))
                    g_iKnifeDelay = str_to_num(szValue)
                else if(equal(szKey, "FORCE_WARMUP"))
                    g_bForceWarmup = bool:str_to_num(szValue)
                else if(equal(szKey, "PAUSE_DURATION"))
                    g_iPauseDuration = str_to_num(szValue)
            }
            case 2: // Commands
            {
                if(equal(szKey, "START_MIX_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_StartMix", g_aStartCmds)
                else if(equal(szKey, "STOP_MIX_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_StopMix", g_aStopCmds)
                else if(equal(szKey, "WARM_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Warmup", g_aWarmCmds)
                else if(equal(szKey, "KNIFE_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_KnifeRound", g_aKnifeCmds)
                else if(equal(szKey, "CHAT_ON_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_ChatOn", g_aChatOnCmds)
                else if(equal(szKey, "CHAT_OFF_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_ChatOff", g_aChatOffCmds)
                else if(equal(szKey, "OVERTIME_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Overtime", g_aOvertimeCmds)
                else if(equal(szKey, "PASSWORD_ON_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_PassOn", g_aPassOnCmds)
                else if(equal(szKey, "PASSWORD_OFF_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_PassOff", g_aPassOffCmds)
                else if(equal(szKey, "SPECALL_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_SpecAll", g_aSpecAllCmds)
                else if(equal(szKey, "RESTART_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Restart", g_aRestartCmds)
                else if(equal(szKey, "SCORE_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Score", g_aScoreCmds)
                else if(equal(szKey, "MOVE_CT_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_MoveCT", g_aMoveCTCmds)
                else if(equal(szKey, "MOVE_TERO_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_MoveT", g_aMoveTCmds)
                else if(equal(szKey, "MOVE_SPEC_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_MoveSpec", g_aMoveSpecCmds)
                else if(equal(szKey, "PAUSE_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Pause", g_aPauseCmds)
            }
            case 3: // Warm Settings
            {
                if(equal(szKey, "WARMUP_SPAWN_MONEY"))
                    g_iWarmMoney = str_to_num(szValue)
            }
        }
    }
    fclose(iFile)

    // Make sure /dm1 is always explicitly registered for Warmup
    RegisterSingleCmd("say /dm1", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say_team /dm1", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say /warm", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say_team /warm", "Cmd_Warmup", g_aWarmCmds)
}

RegisterCommandsFromCSV(const szCSV[], const szFunction[], Array:aHolder)
{
    new szBuffer[192], szToken[64]
    copy(szBuffer, charsmax(szBuffer), szCSV)

    while(szBuffer[0] != EOS && strtok2(szBuffer, szToken, charsmax(szToken), szBuffer, charsmax(szBuffer), ',', TRIM_INNER))
    {
        trim(szToken)
        if(!szToken[0])
            continue

        register_clcmd(szToken, szFunction)
        ArrayPushString(aHolder, szToken)
    }
}

RegisterSingleCmd(const szCmd[], const szFunction[], Array:aHolder)
{
    register_clcmd(szCmd, szFunction)
    ArrayPushString(aHolder, szCmd)
}

RegisterDefaultCommands()
{
    RegisterSingleCmd("say /dm1", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say_team /dm1", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say /warm", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say_team /warm", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say /mix", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say_team /mix", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say /start", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say_team /start", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say /stop", "Cmd_StopMix", g_aStopCmds)
    RegisterSingleCmd("say_team /stop", "Cmd_StopMix", g_aStopCmds)
    RegisterSingleCmd("say /knife", "Cmd_KnifeRound", g_aKnifeCmds)
    RegisterSingleCmd("say_team /knife", "Cmd_KnifeRound", g_aKnifeCmds)
    RegisterSingleCmd("say /score", "Cmd_Score", g_aScoreCmds)
    RegisterSingleCmd("say_team /score", "Cmd_Score", g_aScoreCmds)
    RegisterSingleCmd("say /rr", "Cmd_Restart", g_aRestartCmds)
    RegisterSingleCmd("say /restart", "Cmd_Restart", g_aRestartCmds)
}

// -----------------------------------------------------------------------------
// Client Connection & Info
// -----------------------------------------------------------------------------
public client_putinserver(id)
{
    get_user_name(id, g_szUserName[id], charsmax(g_szUserName[]))
    g_bPlayerVoted[id] = false
    g_bPlayerVotedMix[id] = false
}

public client_disconnected(id)
{
    new szAuthID[36]
    get_user_authid(id, szAuthID, charsmax(szAuthID))

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF)
    {
        ExecuteForward(g_hFwdSysLeaver, g_iRet, szAuthID)
    }

    ExecuteForward(g_hFwdUserSave, g_iRet, id)

    g_szUserName[id][0] = EOS
    g_bPlayerVoted[id] = false
    g_bPlayerVotedMix[id] = false
}

// -----------------------------------------------------------------------------
// ReAPI Hooks: Player Spawn, Killed, Round End, Restart
// -----------------------------------------------------------------------------
public RG_CBasePlayer_Spawn_Post(id)
{
    if(!is_user_alive(id))
        return

    switch(g_iMatchState)
    {
        case STATE_WARMUP:
        {
            // Give $16,000 spawn money for warmup practice
            rg_add_account(id, g_iWarmMoney, AS_SET)
            set_member(id, m_iAccount, g_iWarmMoney)
        }
        case STATE_KNIFE:
        {
            // Strip all weapons and give only knife + vesthelm
            rg_remove_all_items(id)
            rg_give_item(id, "weapon_knife")
            rg_set_user_armor(id, 100, ARMOR_VESTHELM)
            rg_add_account(id, 0, AS_SET)
        }
        case STATE_FIRST_HALF, STATE_SECOND_HALF, STATE_OVERTIME_FIRST_HALF, STATE_OVERTIME_SECOND_HALF:
        {
            // Standard competitive match spawn
        }
    }
}

public RG_CBasePlayer_Killed_Post(iVictim, iKiller, iGib)
{
    if(!is_user_connected(iVictim))
        return

    new szKillerName[MAX_NAME_LENGTH], szKillerAuth[36]
    if(is_user_connected(iKiller))
    {
        get_user_name(iKiller, szKillerName, charsmax(szKillerName))
        get_user_authid(iKiller, szKillerAuth, charsmax(szKillerAuth))
    }

    new bool:bHeadshot = bool:get_member(iVictim, m_bHeadshotKilled)

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF)
    {
        ExecuteForward(g_hFwdPlayerKilled, g_iRet, iKiller, iVictim, bHeadshot, szKillerName, szKillerAuth)
    }
}

public RG_CSGameRules_RestartRound_Post()
{
    // BUGFIX: Reset round score lock when new round starts!
    g_bRoundScored = false
    remove_task(TASK_END_ROUND)
}

public RG_RoundEnd_Post(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
    if(event == ROUND_GAME_RESTART || event == ROUND_GAME_COMMENCE)
        return

    // 1. Warmup Mode: Natural round elimination reset (normal gameplay)
    if(g_iMatchState == STATE_WARMUP)
    {
        return
    }

    // 2. Knife Round Handling
    if(g_iMatchState == STATE_KNIFE)
    {
        if(g_bRoundScored)
            return
        g_bRoundScored = true

        if(status == WINSTATUS_CTS)
            g_iKnifeWinnerTeam = TEAM_CT
        else if(status == WINSTATUS_TERRORISTS)
            g_iKnifeWinnerTeam = TEAM_TERRORIST
        else
            return

        client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "KNIFE_ROUND_WON_BY_X_TEAM", g_iKnifeWinnerTeam == TEAM_CT ? "CT" : "TERRORIST")

        // Start knife side vote directly
        StartKnifeVote()
        return
    }

    // 3. Competitive Match Round Scoring
    if(g_iMatchState != STATE_FIRST_HALF && g_iMatchState != STATE_SECOND_HALF &&
       g_iMatchState != STATE_OVERTIME_FIRST_HALF && g_iMatchState != STATE_OVERTIME_SECOND_HALF)
    {
        return
    }

    // BUGFIX: Prevent double counting bug!
    if(g_bRoundScored)
    {
        return
    }
    g_bRoundScored = true

    new TeamScore:iWinner = TeamScore:-1
    if(status == WINSTATUS_CTS)
    {
        g_iScore[CT_SCORE]++
        iWinner = CT_SCORE
    }
    else if(status == WINSTATUS_TERRORISTS)
    {
        g_iScore[TERO_SCORE]++
        iWinner = TERO_SCORE
    }

    if(iWinner == TeamScore:-1)
        return

    // Announcement of current score
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_SCORE_IS_WITH_END",
        LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE],
        LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])

    if(g_iMatchState == STATE_SECOND_HALF && (g_iFirstHalfScore[CT_SCORE] > 0 || g_iFirstHalfScore[TERO_SCORE] > 0))
    {
        client_print_color(0, print_team_default, "^4%s ^11st Half: ^4CT %d ^3- ^4TR %d", g_szChatPrefix, g_iFirstHalfScore[CT_SCORE], g_iFirstHalfScore[TERO_SCORE])
    }

    // Execute Forward
    new iDuration = get_systime() - g_iMatchStartTime
    ExecuteForward(g_hFwdNewRound, g_iRet, g_iScore[CT_SCORE], g_iScore[TERO_SCORE], iDuration)

    // Schedule round state check
    set_task(1.0, "Task_CheckMatchProgress", TASK_END_ROUND)
}

// -----------------------------------------------------------------------------
// Match Progression & Halftime Logic
// -----------------------------------------------------------------------------
public Task_CheckMatchProgress()
{
    new iTotalRounds = g_iScore[CT_SCORE] + g_iScore[TERO_SCORE]

    // 1. Check First Half Halftime
    if(g_iMatchState == STATE_FIRST_HALF)
    {
        if(iTotalRounds >= 15)
        {
            TriggerHalftime()
            return
        }

        if(iTotalRounds == 14)
        {
            client_print_color(0, print_team_default, "^4%s ^1Last round of the ^4First Half^1!", g_szChatPrefix)
        }
    }
    // 2. Check Second Half Win or Tie
    else if(g_iMatchState == STATE_SECOND_HALF)
    {
        // Check if CT or TR reached win target (16 rounds)
        if(g_iScore[CT_SCORE] >= g_iMixEndRound)
        {
            EndMatch(TEAM_CT)
            return
        }
        else if(g_iScore[TERO_SCORE] >= g_iMixEndRound)
        {
            EndMatch(TEAM_TERRORIST)
            return
        }

        // Check for 15-15 Tie
        if(g_iScore[CT_SCORE] == g_iOvertimeTriggerScore && g_iScore[TERO_SCORE] == g_iOvertimeTriggerScore)
        {
            if(g_bAutoOvertime)
            {
                client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "OVERTIME_AUTOMATIC_WILL_START")
                set_task(5.0, "StartOvertime")
            }
            else
            {
                EndMatch(TEAM_UNASSIGNED) // Draw
            }
            return
        }

        // Pre-last or last round notices
        if(g_iScore[CT_SCORE] == g_iMixEndRound - 1)
        {
            client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_LAST_ROUND_FOR_X_TEAM", "CT")
        }
        else if(g_iScore[TERO_SCORE] == g_iMixEndRound - 1)
        {
            client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_LAST_ROUND_FOR_X_TEAM", "TERRORIST")
        }
    }
    // 3. Overtime Check
    else if(g_iMatchState == STATE_OVERTIME_FIRST_HALF)
    {
        new iOTRounds = g_iOvertimeScore[CT_SCORE] + g_iOvertimeScore[TERO_SCORE]
        if(iOTRounds >= g_iOvertimeRounds)
        {
            TriggerOvertimeHalftime()
        }
    }
    else if(g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        new iTarget = g_iOvertimeTriggerScore + g_iOvertimeRounds + 1
        if(g_iScore[CT_SCORE] >= iTarget)
            EndMatch(TEAM_CT)
        else if(g_iScore[TERO_SCORE] >= iTarget)
            EndMatch(TEAM_TERRORIST)
        else if(g_iScore[CT_SCORE] == iTarget - 1 && g_iScore[TERO_SCORE] == iTarget - 1)
            EndMatch(TEAM_UNASSIGNED) // Tie in OT
    }
}

// -----------------------------------------------------------------------------
// Halftime Execution (BUGFIX: Clean atomic swap & single restart)
// -----------------------------------------------------------------------------
TriggerHalftime()
{
    g_iMatchState = STATE_SECOND_HALF

    // Record exact 1st half score
    g_iFirstHalfScore[CT_SCORE] = g_iScore[CT_SCORE]
    g_iFirstHalfScore[TERO_SCORE] = g_iScore[TERO_SCORE]

    // Swap score variables
    new iTemp = g_iScore[CT_SCORE]
    g_iScore[CT_SCORE] = g_iScore[TERO_SCORE]
    g_iScore[TERO_SCORE] = iTemp

    // Atomically swap all players using ReAPI native
    rg_swap_all_players()

    // Apply configured freeze time for halftime swap
    set_cvar_num("mp_freezetime", g_iFreezeTimeSwap)

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_HALF_SCORE",
        LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE],
        LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])

    set_dhudmessage(0, 150, 255, -1.0, 0.35, 2, 0.1, 4.0, 0.1, 1.0)
    show_dhudmessage(0, "=== HALF TIME ===\nTeams Swapped! Score: CT %d - %d TR", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])

    // Single 4-second delay before restarting into Second Half
    set_task(4.0, "Task_HalftimeRestart")
}

public Task_HalftimeRestart()
{
    server_cmd("sv_restart 1")
    client_print_color(0, print_team_default, "^4%s ^1Second Half is now ^4LIVE! ^1Good Luck!", g_szChatPrefix)
}

// -----------------------------------------------------------------------------
// Overtime Execution
// -----------------------------------------------------------------------------
public StartOvertime()
{
    g_iMatchState = STATE_OVERTIME_FIRST_HALF
    g_iOvertimeScore[CT_SCORE] = 0
    g_iOvertimeScore[TERO_SCORE] = 0

    server_cmd("sv_restart 1")
    client_print_color(0, print_team_default, "^4%s ^1Overtime First Half is ^4LIVE! ^1MR%d", g_szChatPrefix, g_iOvertimeRounds)
}

TriggerOvertimeHalftime()
{
    g_iMatchState = STATE_OVERTIME_SECOND_HALF

    new iTemp = g_iScore[CT_SCORE]
    g_iScore[CT_SCORE] = g_iScore[TERO_SCORE]
    g_iScore[TERO_SCORE] = iTemp

    rg_swap_all_players()

    set_dhudmessage(255, 150, 0, -1.0, 0.35, 2, 0.1, 4.0, 0.1, 1.0)
    show_dhudmessage(0, "=== OVERTIME HALF TIME ===\nTeams Swapped!")

    set_task(3.0, "Task_OvertimeRestart")
}

public Task_OvertimeRestart()
{
    server_cmd("sv_restart 1")
    client_print_color(0, print_team_default, "^4%s ^1Overtime Second Half is ^4LIVE!", g_szChatPrefix)
}

// -----------------------------------------------------------------------------
// Match End
// -----------------------------------------------------------------------------
EndMatch(TeamName:iWinnerTeam)
{
    new iDuration = get_systime() - g_iMatchStartTime

    if(iWinnerTeam == TEAM_CT)
    {
        client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_WON_BY_X_TEAM", "CT")
        set_dhudmessage(0, 200, 0, -1.0, 0.35, 2, 0.1, 5.0, 0.1, 1.0)
        show_dhudmessage(0, "=== MATCH FINISHED ===\nWinner: Counter-Terrorists (%d - %d)", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    }
    else if(iWinnerTeam == TEAM_TERRORIST)
    {
        client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_WON_BY_X_TEAM", "TERRORIST")
        set_dhudmessage(200, 0, 0, -1.0, 0.35, 2, 0.1, 5.0, 0.1, 1.0)
        show_dhudmessage(0, "=== MATCH FINISHED ===\nWinner: Terrorists (%d - %d)", g_iScore[TERO_SCORE], g_iScore[CT_SCORE])
    }
    else
    {
        client_print_color(0, print_team_default, "^4%s ^1Match ended in a ^3DRAW ^1(%d - %d)!", g_szChatPrefix, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
        set_dhudmessage(255, 255, 0, -1.0, 0.35, 2, 0.1, 5.0, 0.1, 1.0)
        show_dhudmessage(0, "=== MATCH FINISHED ===\nResult: DRAW (%d - %d)", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    }

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_END_SCORE",
        LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE],
        LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])

    // Forward winners to other plugins
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        if(get_member(id, m_iTeam) == iWinnerTeam)
        {
            ExecuteForward(g_hFwdMatchWinner, g_iRet, id)
        }
    }

    ExecuteForward(g_hFwdGameOver, g_iRet, 0, iDuration, iWinnerTeam == TEAM_CT ? 'C' : 'T', 0)

    // Automatically transition to Warmup after 10 seconds
    set_task(10.0, "StartWarmup", TASK_MATCH_END)
}

// -----------------------------------------------------------------------------
// Warmup / DM1 Mode Implementation
// -----------------------------------------------------------------------------
public StartWarmup()
{
    remove_task(TASK_HALFTIME_LIVE)
    remove_task(TASK_KNIFE_COUNTDOWN)
    remove_task(TASK_LIVE_COUNTDOWN)
    remove_task(TASK_END_ROUND)
    remove_task(TASK_KNIFE_VOTE)
    remove_task(TASK_TIMEOUT_EXPIRE)
    remove_task(TASK_MIX_VOTE)

    g_iMatchState = STATE_WARMUP
    g_bRoundScored = false
    g_iScore[CT_SCORE] = 0
    g_iScore[TERO_SCORE] = 0
    g_bTeamTimeoutUsed[CT_SCORE] = false
    g_bTeamTimeoutUsed[TERO_SCORE] = false

    // Execute stop config if present
    if(g_szStopConfig[0])
    {
        server_cmd("exec %s", g_szStopConfig)
    }

    // Warmup gameplay rules: normal rounds, $16,000, buy anytime
    set_cvar_num("mp_freezetime", 0)
    set_cvar_num("mp_round_infinite", 0)
    set_cvar_num("mp_buytime", 99)
    set_cvar_num("mp_startmoney", g_iWarmMoney)
    set_cvar_float("mp_roundtime", 1.75)

    server_cmd("sv_restart 1")

    client_print_color(0, print_team_default, "^4%s ^1WarmUp / DM1 mode is now ^4ACTIVE^1! Type ^3/dm1 ^1or ^3/warm", g_szChatPrefix)
    client_print_color(0, print_team_default, "^4%s ^1Practice freely with ^4$16,000^1! Rounds reset on team elimination.", g_szChatPrefix)
}

// -----------------------------------------------------------------------------
// /mix Global Vote: Knife Round vs Direct Live
// -----------------------------------------------------------------------------
StartMixVote()
{
    remove_task(TASK_MIX_VOTE)

    g_iMixVoteKnife = 0
    g_iMixVoteLive = 0
    g_iMixVoteTimer = 10

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        g_bPlayerVotedMix[id] = false
        ShowMixVoteMenu(id)
    }

    set_task(1.0, "Task_MixVoteCountdown", TASK_MIX_VOTE, .flags = "b")
}

ShowMixVoteMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Match Start Mode:\w", "Menu_MixVoteHandler")

    menu_additem(iMenu, "\w1. Knife Round \y(Winner picks side)\w", "1")
    menu_additem(iMenu, "\w2. Direct Live \y(Start match now)\w", "2")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_NEVER)
    menu_display(id, iMenu, 0)
}

public Menu_MixVoteHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT || g_bPlayerVotedMix[id])
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)

    new iChoice = str_to_num(szData)
    g_bPlayerVotedMix[id] = true

    if(iChoice == 1)
    {
        g_iMixVoteKnife++
        client_print_color(id, print_team_default, "^4%s ^1You voted for: ^3Knife Round^1.", g_szChatPrefix)
    }
    else
    {
        g_iMixVoteLive++
        client_print_color(id, print_team_default, "^4%s ^1You voted for: ^4Direct Live^1.", g_szChatPrefix)
    }

    menu_destroy(iMenu)
    return PLUGIN_HANDLED
}

public Task_MixVoteCountdown()
{
    g_iMixVoteTimer--

    if(g_iMixVoteTimer <= 0)
    {
        remove_task(TASK_MIX_VOTE)
        FinishMixVote()
        return
    }

    set_hudmessage(0, 200, 255, -1.0, 0.22, 0, 0.0, 0.9, 0.0, 0.1)
    show_hudmessage(0, "Match Start Vote: %d seconds left\n[1] Knife Round: %d | [2] Direct Live: %d",
        g_iMixVoteTimer, g_iMixVoteKnife, g_iMixVoteLive)
}

FinishMixVote()
{
    // Close vote menus on all players
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        menu_cancel(iPlayers[i])
    }

    client_print_color(0, print_team_default, "^4%s ^1Vote Finished: ^3Knife Round: %d ^1| ^4Direct Live: %d",
        g_szChatPrefix, g_iMixVoteKnife, g_iMixVoteLive)

    if(g_iMixVoteLive > g_iMixVoteKnife)
    {
        client_print_color(0, print_team_default, "^4%s ^1Winner: ^4Direct Live^1! Match countdown starting...", g_szChatPrefix)
        StartLiveCountdown()
    }
    else
    {
        client_print_color(0, print_team_default, "^4%s ^1Winner: ^3Knife Round^1! Knife round starting...", g_szChatPrefix)
        StartKnifeRound()
    }
}

// -----------------------------------------------------------------------------
// Knife Round & Side Vote Implementation (Zero HLTV / No Demo Menus)
// -----------------------------------------------------------------------------
public StartKnifeRound()
{
    g_iMatchState = STATE_KNIFE
    g_bRoundScored = false
    g_iKnifeWinnerTeam = TEAM_UNASSIGNED
    g_iVoteStay = 0
    g_iVoteSwitch = 0

    if(g_szStopConfig[0])
    {
        server_cmd("exec %s", g_szStopConfig)
    }

    set_cvar_num("mp_freezetime", 3)
    set_cvar_num("mp_buytime", 0)
    set_cvar_float("mp_roundtime", 35.0)

    server_cmd("sv_restart 1")

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "KNIFE_STARTED")
}

StartKnifeVote()
{
    g_iVoteStay = 0
    g_iVoteSwitch = 0
    g_iKnifeVoteTimer = g_iKnifeDelay > 0 ? g_iKnifeDelay : 10

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        g_bPlayerVoted[id] = false

        new TeamName:team = get_member(id, m_iTeam)
        if(team == g_iKnifeWinnerTeam)
        {
            ShowKnifeSideMenu(id)
        }
    }

    set_task(1.0, "Task_KnifeVoteCountdown", TASK_KNIFE_VOTE, .flags = "b")
}

ShowKnifeSideMenu(id)
{
    new iMenu = menu_create("\yChoose Starting Side:\w", "Menu_KnifeSideHandler")

    menu_additem(iMenu, "\wStay on current side", "1")
    menu_additem(iMenu, "\wSwitch to other side", "2")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_NEVER)
    menu_display(id, iMenu, 0)
}

public Menu_KnifeSideHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT || g_bPlayerVoted[id])
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)

    new iChoice = str_to_num(szData)
    g_bPlayerVoted[id] = true

    if(iChoice == 1)
    {
        g_iVoteStay++
        client_print_color(id, print_team_default, "^4%s ^1You voted to ^4STAY^1.", g_szChatPrefix)
    }
    else
    {
        g_iVoteSwitch++
        client_print_color(id, print_team_default, "^4%s ^1You voted to ^4SWITCH^1.", g_szChatPrefix)
    }

    menu_destroy(iMenu)
    return PLUGIN_HANDLED
}

public Task_KnifeVoteCountdown()
{
    g_iKnifeVoteTimer--

    if(g_iKnifeVoteTimer <= 0)
    {
        remove_task(TASK_KNIFE_VOTE)
        FinishKnifeVote()
        return
    }

    set_hudmessage(0, 200, 255, -1.0, 0.25, 0, 0.0, 0.9, 0.0, 0.1)
    show_hudmessage(0, "Side Choice Vote: %d seconds left\nStay: %d | Switch: %d", g_iKnifeVoteTimer, g_iVoteStay, g_iVoteSwitch)
}

FinishKnifeVote()
{
    // Close menus on all players
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        menu_cancel(iPlayers[i])
    }

    new bool:bDoSwitch = (g_iVoteSwitch > g_iVoteStay)

    if(bDoSwitch)
    {
        client_print_color(0, print_team_default, "^4%s %L %L", g_szChatPrefix, LANG_SERVER, "TEAM_VOTED", LANG_SERVER, "SWITCH")
        rg_swap_all_players()
    }
    else
    {
        client_print_color(0, print_team_default, "^4%s %L %L", g_szChatPrefix, LANG_SERVER, "TEAM_VOTED", LANG_SERVER, "STAY")
    }

    // Direct transition into LIVE match countdown (ZERO demo menus)
    StartLiveCountdown()
}

// -----------------------------------------------------------------------------
// Live Match Countdown & Start
// -----------------------------------------------------------------------------
StartLiveCountdown()
{
    g_iLiveCountdown = 3
    set_task(1.0, "Task_LiveCountdownLoop", TASK_LIVE_COUNTDOWN, .flags = "b")
}

public Task_LiveCountdownLoop()
{
    if(g_iLiveCountdown > 0)
    {
        set_dhudmessage(255, 100, 0, -1.0, 0.35, 1, 0.1, 0.8, 0.1, 0.1)
        show_dhudmessage(0, "Match Starting in %d...", g_iLiveCountdown)
        server_cmd("sv_restart 1")
        g_iLiveCountdown--
        return
    }

    remove_task(TASK_LIVE_COUNTDOWN)
    StartMatchLive()
}

StartMatchLive()
{
    g_iMatchState = STATE_FIRST_HALF
    g_iScore[CT_SCORE] = 0
    g_iScore[TERO_SCORE] = 0
    g_iFirstHalfScore[CT_SCORE] = 0
    g_iFirstHalfScore[TERO_SCORE] = 0
    g_bRoundScored = false
    g_bTeamTimeoutUsed[CT_SCORE] = false
    g_bTeamTimeoutUsed[TERO_SCORE] = false
    g_iMatchStartTime = get_systime()

    if(g_szStartConfig[0])
    {
        server_cmd("exec %s", g_szStartConfig)
    }

    set_cvar_num("mp_freezetime", 15)
    set_cvar_num("mp_buytime", 15)
    set_cvar_num("mp_startmoney", 800)
    set_cvar_float("mp_roundtime", 1.75)

    server_cmd("sv_restart 1")

    set_dhudmessage(0, 255, 0, -1.0, 0.30, 2, 0.1, 4.0, 0.1, 1.0)
    show_dhudmessage(0, "=== MATCH IS LIVE! ===\nGL & HF!")

    client_print_color(0, print_team_default, "^4%s ^1=== MATCH IS ^4LIVE^1! Good Luck & Have Fun! ===", g_szChatPrefix)

    ExecuteForward(g_hFwdGameBeginPre, g_iRet)

    // Notify post forward for all connected players
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        new szAuth[36]
        get_user_authid(id, szAuth, charsmax(szAuth))
        ExecuteForward(g_hFwdGameBeginPost, g_iRet, id, (i == iNum - 1) ? 1 : 0, szAuth, g_szUserName[id], 0)
    }
}

// -----------------------------------------------------------------------------
// HUD Display & Status Banner
// -----------------------------------------------------------------------------
public Task_HudDisplay()
{
    static szMsg[256]

    switch(g_iMatchState)
    {
        case STATE_WARMUP:
        {
            formatex(szMsg, charsmax(szMsg), "[ WARMUP / DM1 ]\nSpawn Money: $16,000 | Type /mix or /a to start");
            set_hudmessage(0, 200, 255, 0.02, 0.20, 0, 0.0, 1.1, 0.0, 0.0)
            ShowSyncHudMsg(0, g_iHudSync, szMsg)
        }
        case STATE_KNIFE:
        {
            formatex(szMsg, charsmax(szMsg), "[ KNIFE ROUND ]\nFight for side selection!")
            set_hudmessage(255, 150, 0, 0.02, 0.20, 0, 0.0, 1.1, 0.0, 0.0)
            ShowSyncHudMsg(0, g_iHudSync, szMsg)
        }
        case STATE_FIRST_HALF:
        {
            formatex(szMsg, charsmax(szMsg), "[ 1st Half ] Score: CT %d - %d TR\nRound %d of 15",
                g_iScore[CT_SCORE], g_iScore[TERO_SCORE], (g_iScore[CT_SCORE] + g_iScore[TERO_SCORE] + 1))
            set_hudmessage(100, 255, 100, 0.02, 0.20, 0, 0.0, 1.1, 0.0, 0.0)
            ShowSyncHudMsg(0, g_iHudSync, szMsg)
        }
        case STATE_SECOND_HALF:
        {
            formatex(szMsg, charsmax(szMsg), "[ 2nd Half ] Score: CT %d - %d TR\nTarget: %d Rounds",
                g_iScore[CT_SCORE], g_iScore[TERO_SCORE], g_iMixEndRound)
            set_hudmessage(100, 255, 100, 0.02, 0.20, 0, 0.0, 1.1, 0.0, 0.0)
            ShowSyncHudMsg(0, g_iHudSync, szMsg)
        }
        case STATE_OVERTIME_FIRST_HALF, STATE_OVERTIME_SECOND_HALF:
        {
            formatex(szMsg, charsmax(szMsg), "[ OVERTIME ] Score: CT %d - %d TR",
                g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
            set_hudmessage(255, 200, 0, 0.02, 0.20, 0, 0.0, 1.1, 0.0, 0.0)
            ShowSyncHudMsg(0, g_iHudSync, szMsg)
        }
    }
}

// -----------------------------------------------------------------------------
// Admin & Client Commands Handlers
// -----------------------------------------------------------------------------
bool:HasAdminAccess(id)
{
    if(!id)
        return true
    return bool:(get_user_flags(id) & read_flags(g_szAdminAccess))
}

bool:HasRconOrBanAccess(id)
{
    if(!id)
        return true
    new iFlags = get_user_flags(id)
    return bool:(iFlags & ADMIN_RCON || iFlags & ADMIN_BAN || iFlags & ADMIN_IMMUNITY)
}

public Cmd_StartMix(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF)
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_ALREADY_STARTED")
        return PLUGIN_HANDLED
    }

    if(task_exists(TASK_MIX_VOTE))
    {
        client_print_color(id, print_team_default, "^4%s ^1A match vote is already in progress!", g_szChatPrefix)
        return PLUGIN_HANDLED
    }

    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1started match vote: ^3[1] Knife Round ^1vs ^4[2] Direct Live^1!", g_szChatPrefix, g_szUserName[id])
    StartMixVote()
    return PLUGIN_HANDLED
}

public Cmd_DirectLive(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF)
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_ALREADY_STARTED")
        return PLUGIN_HANDLED
    }

    remove_task(TASK_MIX_VOTE)
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1forced ^4Direct Live^1 match!", g_szChatPrefix, g_szUserName[id])
    StartLiveCountdown()
    return PLUGIN_HANDLED
}

public Cmd_StopMix(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_STOPPED_BY_X", g_szUserName[id])
    
    new iDuration = get_systime() - g_iMatchStartTime
    ExecuteForward(g_hFwdGameStopped, g_iRet, id, iDuration, 0)

    StartWarmup()
    return PLUGIN_HANDLED
}

public Cmd_Warmup(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    StartWarmup()
    return PLUGIN_HANDLED
}

public Cmd_KnifeRound(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    remove_task(TASK_MIX_VOTE)
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1forced ^3Knife Round^1!", g_szChatPrefix, g_szUserName[id])
    StartKnifeRound()
    return PLUGIN_HANDLED
}

public Cmd_Score(id)
{
    if(g_iMatchState == STATE_WARMUP)
    {
        client_print_color(id, print_team_default, "^4%s ^1Server is currently in ^4Warmup / DM1^1 mode.", g_szChatPrefix)
        return PLUGIN_HANDLED
    }

    client_print_color(id, print_team_default, "^4%s ^1Current Score: ^4CT %d ^1- ^4TR %d", g_szChatPrefix, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    if(g_iMatchState == STATE_SECOND_HALF && (g_iFirstHalfScore[CT_SCORE] > 0 || g_iFirstHalfScore[TERO_SCORE] > 0))
    {
        client_print_color(id, print_team_default, "^4%s ^11st Half: ^4CT %d ^3- ^4TR %d", g_szChatPrefix, g_iFirstHalfScore[CT_SCORE], g_iFirstHalfScore[TERO_SCORE])
    }
    return PLUGIN_HANDLED
}

public Cmd_Restart(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    server_cmd("sv_restart 1")
    client_print_color(0, print_team_default, "^4%s ^1Round restarted by ^4%s^1.", g_szChatPrefix, g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_ChatOn(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    g_bChatMuted = false
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "CHAT_OPENED_BY_X", g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_ChatOff(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    g_bChatMuted = true
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "CHAT_CLOSED_BY_X", g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_PassOn(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szPass[32]
    read_argv(1, szPass, charsmax(szPass))
    if(!szPass[0])
        copy(szPass, charsmax(szPass), "mix")

    server_cmd("sv_password ^"%s^"", szPass)
    client_print_color(id, print_team_default, "^4%s ^1Server password set to: ^4%s", g_szChatPrefix, szPass)
    return PLUGIN_HANDLED
}

public Cmd_PassOff(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    server_cmd("sv_password ^"^"")
    client_print_color(id, print_team_default, "^4%s ^1Server password has been ^4removed^1.", g_szChatPrefix)
    return PLUGIN_HANDLED
}

public Cmd_SpecAll(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        rg_set_user_team(iPlayers[i], TEAM_SPECTATOR)
    }

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "PLAYERS_MOVED_SPEC_BY_X", g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_MoveCT(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szTarget[32]
    read_argv(1, szTarget, charsmax(szTarget))
    new iTarget = cmd_target(id, szTarget, CMDTARGET_NO_BOTS)
    if(!iTarget)
        return PLUGIN_HANDLED

    rg_set_user_team(iTarget, TEAM_CT)
    client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^4CT^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[iTarget], g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_MoveT(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szTarget[32]
    read_argv(1, szTarget, charsmax(szTarget))
    new iTarget = cmd_target(id, szTarget, CMDTARGET_NO_BOTS)
    if(!iTarget)
        return PLUGIN_HANDLED

    rg_set_user_team(iTarget, TEAM_TERRORIST)
    client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^4TERRORIST^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[iTarget], g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_MoveSpec(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szTarget[32]
    read_argv(1, szTarget, charsmax(szTarget))
    new iTarget = cmd_target(id, szTarget, CMDTARGET_NO_BOTS)
    if(!iTarget)
        return PLUGIN_HANDLED

    rg_set_user_team(iTarget, TEAM_SPECTATOR)
    client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^4SPECTATOR^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[iTarget], g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_Pause(id)
{
    // If admin calls pause, direct toggle
    if(HasAdminAccess(id))
    {
        if(!g_bPaused)
        {
            g_bPaused = true
            server_cmd("pausable 1; pause")
            client_print_color(0, print_team_default, "^4%s ^1Match has been ^4PAUSED^1 by Admin ^4%s^1.", g_szChatPrefix, g_szUserName[id])
        }
        else
        {
            g_bPaused = false
            server_cmd("pause; pausable 0")
            client_print_color(0, print_team_default, "^4%s ^1Match has been ^4UNPAUSED^1 by Admin ^4%s^1.", g_szChatPrefix, g_szUserName[id])
        }
        return PLUGIN_HANDLED
    }

    // Player tactical timeout request
    if(g_iMatchState != STATE_FIRST_HALF && g_iMatchState != STATE_SECOND_HALF)
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_NOT_STARTED_YET")
        return PLUGIN_HANDLED
    }

    new TeamName:team = get_member(id, m_iTeam)
    new TeamScore:tScore = (team == TEAM_CT) ? CT_SCORE : TERO_SCORE

    if(g_bTeamTimeoutUsed[tScore])
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOUR_TEAM_ALREADY_TIMEOUT")
        return PLUGIN_HANDLED
    }

    g_bTeamTimeoutUsed[tScore] = true
    g_iPauseTimer = g_iPauseDuration > 0 ? g_iPauseDuration : 60
    g_bPaused = true

    server_cmd("pausable 1; pause")
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "PLAYER_X_REQUESTED_TIMEOUT", g_szUserName[id])

    set_task(1.0, "Task_TimeoutCountdown", TASK_TIMEOUT_EXPIRE, .flags = "b")
    return PLUGIN_HANDLED
}

public Task_TimeoutCountdown()
{
    g_iPauseTimer--

    if(g_iPauseTimer <= 0)
    {
        remove_task(TASK_TIMEOUT_EXPIRE)
        g_bPaused = false
        server_cmd("pause; pausable 0")
        client_print_color(0, print_team_default, "^4%s ^1Timeout expired! Match resumed.", g_szChatPrefix)
        return
    }

    set_hudmessage(255, 200, 0, -1.0, 0.40, 0, 0.0, 0.9, 0.0, 0.1)
    show_hudmessage(0, "Tactical Timeout: %d seconds remaining", g_iPauseTimer)
}

public Cmd_Overtime(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    StartOvertime()
    return PLUGIN_HANDLED
}

public Cmd_ShowCommands(id)
{
    client_print_color(id, print_team_default, "^4%s ^1=== Available Mix Commands ===", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/a ^1: Master Admin Control Panel", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/dm1 ^1or ^3/warm ^1: Warmup Mode ($16,000 practice)", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/mix ^1or ^3/start ^1: Vote Knife Round vs Direct Live", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/knife ^1: Direct Knife Round for side choice", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/live ^1: Direct Live match start", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/stop ^1: Stop match and return to warmup", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/score ^1: Show current round scores", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/pause ^1: Request tactical timeout or pause", g_szChatPrefix)
    return PLUGIN_HANDLED
}

// -----------------------------------------------------------------------------
// MASTER /a ADMIN CONTROL PANEL & ADMIN MANAGER
// -----------------------------------------------------------------------------
public Cmd_AdminDashboard(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    new iMenu = menu_create("\y[GAMELAND] Master Admin Panel\w", "Menu_DashboardHandler")

    menu_additem(iMenu, "\rAdmin Manager \y(Add Admins to users.ini)\w", "1")
    menu_additem(iMenu, "\yMatch & Mix Controls\w", "2")
    menu_additem(iMenu, "\wTeam Management \y(Swap / Move / Spec)\w", "3")
    menu_additem(iMenu, "\wServer Settings \y(Restart, Alltalk, Pass)\w", "4")
    menu_additem(iMenu, "\wMap Controls \y(Map Menu / Vote Map)\w", "5")
    menu_additem(iMenu, "\wPlayer Moderation \y(Kick / Ban / Slap)\w", "6")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
    return PLUGIN_HANDLED
}

public Menu_DashboardHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: ShowAdminManagerMenu(id)
        case 2: ShowMatchControlMenu(id)
        case 3: ShowTeamControlMenu(id)
        case 4: ShowServerControlMenu(id)
        case 5: ShowMapControlMenu(id)
        case 6: ShowModerationMenu(id)
    }
    return PLUGIN_HANDLED
}

// --- 1. ADMIN MANAGER WIZARD ---
ShowAdminManagerMenu(id)
{
    if(!HasRconOrBanAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s ^1You need ^4RCON / High Admin^1 privilege to access Admin Manager!", g_szChatPrefix)
        Cmd_AdminDashboard(id)
        return
    }

    new iMenu = menu_create("\y[GAMELAND] Admin Manager:\w", "Menu_AdminManagerHandler")

    menu_additem(iMenu, "\wAdd Admin from \yConnected Players\w", "1")
    menu_additem(iMenu, "\wReload Admins from \yusers.ini\w", "2")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_AdminManagerHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: ShowSelectPlayerForAdmin(id)
        case 2:
        {
            server_cmd("amx_reloadadmins")
            client_print_color(id, print_team_default, "^4%s ^1Admins reloaded successfully from ^4users.ini^1!", g_szChatPrefix)
            ShowAdminManagerMenu(id)
        }
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

ShowSelectPlayerForAdmin(id)
{
    new iMenu = menu_create("\ySelect Player to Make Admin:\w", "Menu_SelectPlayerAdminHandler")

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new player = iPlayers[i]
        new szInfo[6], szDisplay[96], szAuth[36]
        num_to_str(player, szInfo, charsmax(szInfo))
        get_user_authid(player, szAuth, charsmax(szAuth))

        formatex(szDisplay, charsmax(szDisplay), "\w%s \d[%s]", g_szUserName[player], szAuth)
        menu_additem(iMenu, szDisplay, szInfo)
    }

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_SelectPlayerAdminHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new iTarget = str_to_num(szData)
    if(!is_user_connected(iTarget))
    {
        client_print_color(id, print_team_default, "^4%s ^1Selected player is no longer connected.", g_szChatPrefix)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    g_eAdminSession[id][SessionTargetId] = iTarget
    copy(g_eAdminSession[id][SessionName], charsmax(g_eAdminSession[][SessionName]), g_szUserName[iTarget])
    get_user_authid(iTarget, g_eAdminSession[id][SessionAuth], charsmax(g_eAdminSession[][SessionAuth]))

    ShowAdminPresetMenu(id)
    return PLUGIN_HANDLED
}

ShowAdminPresetMenu(id)
{
    new szTitle[96]
    formatex(szTitle, charsmax(szTitle), "\yAssign Permissions for: \w%s", g_eAdminSession[id][SessionName])
    new iMenu = menu_create(szTitle, "Menu_AdminPresetHandler")

    menu_additem(iMenu, "\rFull Owner \d[abcdefghijklmnopqrstu]", "1")
    menu_additem(iMenu, "\yHead Admin \d[abcdefghijklmnopqrst]", "2")
    menu_additem(iMenu, "\wMatch Admin \d[bcdefij]", "3")
    menu_additem(iMenu, "\wBasic Admin \d[cdeij]", "4")
    menu_additem(iMenu, "\wVIP Member \d[bit]", "5")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_AdminPresetHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "abcdefghijklmnopqrstu")
        case 2: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "abcdefghijklmnopqrst")
        case 3: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "bcdefij")
        case 4: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "cdeij")
        case 5: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "bit")
    }

    ShowAdminAuthTypeMenu(id)
    return PLUGIN_HANDLED
}

ShowAdminAuthTypeMenu(id)
{
    new iMenu = menu_create("\ySelect Authentication Method:\w", "Menu_AdminAuthTypeHandler")

    new szItem1[96]
    formatex(szItem1, charsmax(szItem1), "\wSteamID Auth \y[%s] \d(flag 'ce')", g_eAdminSession[id][SessionAuth])
    menu_additem(iMenu, szItem1, "1")

    new szItem2[96]
    formatex(szItem2, charsmax(szItem2), "\wNickname Auth \y[%s] \d(pass: 123456, flag 'a')", g_eAdminSession[id][SessionName])
    menu_additem(iMenu, szItem2, "2")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_AdminAuthTypeHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    if(str_to_num(szData) == 1)
    {
        // SteamID Auth
        copy(g_eAdminSession[id][SessionAccountFlags], charsmax(g_eAdminSession[][SessionAccountFlags]), "ce")
        copy(g_eAdminSession[id][SessionPassword], charsmax(g_eAdminSession[][SessionPassword]), "")
        CommitAdminToFile(id, false)
    }
    else
    {
        // Nickname Auth
        copy(g_eAdminSession[id][SessionAccountFlags], charsmax(g_eAdminSession[][SessionAccountFlags]), "a")
        copy(g_eAdminSession[id][SessionPassword], charsmax(g_eAdminSession[][SessionPassword]), "123456")
        CommitAdminToFile(id, true)
    }
    return PLUGIN_HANDLED
}

CommitAdminToFile(id, bool:bUseNick)
{
    new szConfigDir[128], szUsersFile[128]
    get_configsdir(szConfigDir, charsmax(szConfigDir))
    formatex(szUsersFile, charsmax(szUsersFile), "%s/users.ini", szConfigDir)

    new iFile = fopen(szUsersFile, "at")
    if(!iFile)
    {
        client_print_color(id, print_team_default, "^4%s ^1Failed to open ^4users.ini^1 for writing!", g_szChatPrefix)
        return
    }

    new szAuthIdentifier[64]
    if(bUseNick)
    {
        copy(szAuthIdentifier, charsmax(szAuthIdentifier), g_eAdminSession[id][SessionName])
    }
    else
    {
        copy(szAuthIdentifier, charsmax(szAuthIdentifier), g_eAdminSession[id][SessionAuth])
    }

    fprintf(iFile, "^n^"%s^" ^"%s^" ^"%s^" ^"%s^" ; Added by %s via /a menu^n",
        szAuthIdentifier,
        g_eAdminSession[id][SessionPassword],
        g_eAdminSession[id][SessionFlags],
        g_eAdminSession[id][SessionAccountFlags],
        g_szUserName[id])

    fclose(iFile)

    // Reload admins into memory
    server_cmd("amx_reloadadmins")

    client_print_color(id, print_team_default, "^4%s ^1Successfully added ^4%s ^1as Admin!", g_szChatPrefix, g_eAdminSession[id][SessionName])
    client_print_color(id, print_team_default, "^4%s ^1Flags: ^3%s ^1| Auth: ^3%s ^1| Type: ^3%s",
        g_szChatPrefix,
        g_eAdminSession[id][SessionFlags],
        szAuthIdentifier,
        bUseNick ? "Name (pass: 123456)" : "SteamID (ce)")

    // Notify player if connected
    new iTarget = g_eAdminSession[id][SessionTargetId]
    if(is_user_connected(iTarget))
    {
        client_print_color(iTarget, print_team_default, "^4[GAMELAND] ^1You have been granted Admin rights by ^3%s^1! Reconnect to apply.", g_szUserName[id])
    }
}

// --- 2. MATCH & MIX CONTROLS ---
ShowMatchControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Match & Mix Control:\w", "Menu_MatchControlHandler")

    menu_additem(iMenu, "\wStart Match \y(Trigger Global Vote)\w", "1")
    menu_additem(iMenu, "\rForce Direct Live \y(Skip Knife/Vote)\w", "2")
    menu_additem(iMenu, "\yForce Knife Round \y(Side selection)\w", "3")
    menu_additem(iMenu, "\wWarmup / DM1 Mode \y($16,000 practice)\w", "4")
    menu_additem(iMenu, "\wStop Match \y(Return to Warmup)\w", "5")
    menu_additem(iMenu, "\wPause / Unpause Match\w", "6")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_MatchControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: Cmd_StartMix(id)
        case 2: Cmd_DirectLive(id)
        case 3: Cmd_KnifeRound(id)
        case 4: Cmd_Warmup(id)
        case 5: Cmd_StopMix(id)
        case 6: Cmd_Pause(id)
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// --- 3. TEAM CONTROLS ---
ShowTeamControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Team Management:\w", "Menu_TeamControlHandler")

    menu_additem(iMenu, "\ySwap All Teams \w(CT <-> TR)", "1")
    menu_additem(iMenu, "\wMove All Players to \ySpectator\w", "2")
    menu_additem(iMenu, "\wMove Single Player to \yCT\w", "3")
    menu_additem(iMenu, "\wMove Single Player to \yTERRORIST\w", "4")
    menu_additem(iMenu, "\wMove Single Player to \ySPECTATOR\w", "5")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_TeamControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1:
        {
            rg_swap_all_players()
            client_print_color(0, print_team_default, "^4%s ^1Teams swapped by Admin ^4%s^1.", g_szChatPrefix, g_szUserName[id])
            ShowTeamControlMenu(id)
        }
        case 2:
        {
            Cmd_SpecAll(id)
            ShowTeamControlMenu(id)
        }
        case 3: ShowMovePlayerMenu(id, TEAM_CT)
        case 4: ShowMovePlayerMenu(id, TEAM_TERRORIST)
        case 5: ShowMovePlayerMenu(id, TEAM_SPECTATOR)
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

ShowMovePlayerMenu(id, TeamName:targetTeam)
{
    new szTitle[64]
    formatex(szTitle, charsmax(szTitle), "\yMove Player to %s:\w", targetTeam == TEAM_CT ? "CT" : (targetTeam == TEAM_TERRORIST ? "TERRORIST" : "SPECTATOR"))
    new iMenu = menu_create(szTitle, "Menu_MovePlayerTargetHandler")

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new player = iPlayers[i]
        new szInfo[12], szDisplay[64]
        formatex(szInfo, charsmax(szInfo), "%d %d", player, _:targetTeam)
        formatex(szDisplay, charsmax(szDisplay), "\w%s", g_szUserName[player])
        menu_additem(iMenu, szDisplay, szInfo)
    }

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_MovePlayerTargetHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowTeamControlMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[12], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new szPlayer[6], szTeam[6]
    strtok(szData, szPlayer, charsmax(szPlayer), szTeam, charsmax(szTeam), ' ')

    new iTarget = str_to_num(szPlayer)
    new TeamName:team = TeamName:str_to_num(szTeam)

    if(is_user_connected(iTarget))
    {
        rg_set_user_team(iTarget, team)
        client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^3%s ^1by ^4%s^1.",
            g_szChatPrefix, g_szUserName[iTarget],
            team == TEAM_CT ? "CT" : (team == TEAM_TERRORIST ? "TERRORIST" : "SPECTATOR"),
            g_szUserName[id])
    }
    ShowTeamControlMenu(id)
    return PLUGIN_HANDLED
}

// --- 4. SERVER & AUDIO CONTROLS ---
ShowServerControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Server & Audio Controls:\w", "Menu_ServerControlHandler")

    menu_additem(iMenu, "\wRestart Round 1s \y(/rr)\w", "1")
    menu_additem(iMenu, "\wAlltalk \yON \d(sv_alltalk 1)\w", "2")
    menu_additem(iMenu, "\wAlltalk \yOFF \d(sv_alltalk 0)\w", "3")
    menu_additem(iMenu, "\wMute Chat \yON \d(/off)\w", "4")
    menu_additem(iMenu, "\wMute Chat \yOFF \d(/on)\w", "5")
    menu_additem(iMenu, "\wSet Server Password \y(/passon)\w", "6")
    menu_additem(iMenu, "\wRemove Server Password \y(/passoff)\w", "7")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_ServerControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: Cmd_Restart(id)
        case 2:
        {
            set_cvar_num("sv_alltalk", 1)
            client_print_color(0, print_team_default, "^4%s ^1sv_alltalk set to ^41 (ON)^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[id])
            ShowServerControlMenu(id)
        }
        case 3:
        {
            set_cvar_num("sv_alltalk", 0)
            client_print_color(0, print_team_default, "^4%s ^1sv_alltalk set to ^40 (OFF)^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[id])
            ShowServerControlMenu(id)
        }
        case 4:
        {
            Cmd_ChatOff(id)
            ShowServerControlMenu(id)
        }
        case 5:
        {
            Cmd_ChatOn(id)
            ShowServerControlMenu(id)
        }
        case 6:
        {
            Cmd_PassOn(id)
            ShowServerControlMenu(id)
        }
        case 7:
        {
            Cmd_PassOff(id)
            ShowServerControlMenu(id)
        }
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// --- 5. MAP CONTROLS ---
ShowMapControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Map Management:\w", "Menu_MapControlHandler")

    menu_additem(iMenu, "\wOpen Standard Map Menu \d(amx_mapmenu)\w", "1")
    menu_additem(iMenu, "\wVote Map Menu \d(amx_votemap)\w", "2")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_MapControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: client_cmd(id, "amx_mapmenu")
        case 2: client_cmd(id, "say /vm")
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// --- 6. MODERATION CONTROLS ---
ShowModerationMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Player Moderation:\w", "Menu_ModerationHandler")

    menu_additem(iMenu, "\wKick Player Menu \d(amx_kickmenu)\w", "1")
    menu_additem(iMenu, "\wBan Player Menu \d(amx_banmenu)\w", "2")
    menu_additem(iMenu, "\wSlap / Slay Menu \d(amx_slapmenu)\w", "3")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_ModerationHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: client_cmd(id, "amx_kickmenu")
        case 2: client_cmd(id, "amx_banmenu")
        case 3: client_cmd(id, "amx_slapmenu")
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// -----------------------------------------------------------------------------
// Chat management
// -----------------------------------------------------------------------------
public Hook_Say(id)
{
    if(g_bChatMuted && !HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s ^1Chat is currently muted by an Administrator.", g_szChatPrefix)
        return PLUGIN_HANDLED
    }
    return PLUGIN_CONTINUE
}

public Hook_SayTeam(id)
{
    return PLUGIN_CONTINUE
}

// -----------------------------------------------------------------------------
// Natives Implementation
// -----------------------------------------------------------------------------
public native_is_half(iPlugin, iParams)
{
    return (g_iMatchState == STATE_FIRST_HALF && (g_iScore[CT_SCORE] + g_iScore[TERO_SCORE]) >= 15)
}

public native_is_last_round(iPlugin, iParams)
{
    if(g_iMatchState == STATE_SECOND_HALF)
    {
        return (g_iScore[CT_SCORE] == g_iMixEndRound - 1 || g_iScore[TERO_SCORE] == g_iMixEndRound - 1)
    }
    return false
}

public native_is_prelast_round(iPlugin, iParams)
{
    if(g_iMatchState == STATE_SECOND_HALF)
    {
        return (g_iScore[CT_SCORE] == g_iMixEndRound - 2 || g_iScore[TERO_SCORE] == g_iMixEndRound - 2)
    }
    return false
}

public native_can_overtime(iPlugin, iParams)
{
    return (g_iScore[CT_SCORE] == g_iOvertimeTriggerScore && g_iScore[TERO_SCORE] == g_iOvertimeTriggerScore)
}

public native_is_started(iPlugin, iParams)
{
    return (g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF ||
            g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
}

public native_is_warm(iPlugin, iParams)
{
    return (g_iMatchState == STATE_WARMUP)
}

public native_get_prefix(iPlugin, iParams)
{
    set_string(1, g_szChatPrefix, get_param(2))
}

public native_get_username(iPlugin, iParams)
{
    new id = get_param(1)
    if(id < 1 || id > MaxClients)
        return -1

    set_string(2, g_szUserName[id], get_param(3))
    return 1
}

// Backwards compatibility dummies (Points & SQL removed)
public native_user_points(iPlugin, iParams)
{
    return 0
}

public bool:native_has_points_sys(iPlugin, iParams)
{
    return false
}

public native_search_for_user(iPlugin, iParams)
{
    return -1
}

public native_multiply_factor(iPlugin, iParams)
{
    return 1
}

public native_get_points_table(iPlugin, iParams)
{
    set_string(1, "", get_param(2))
    return 0
}
