#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "GameLand Fast-Duck & Weapon Fixer"
#define VERSION "2.1.0"
#define AUTHOR  "GAMELAND"

#define MAX_PLAYERS 32

// CS 1.6 Player Offsets (CBasePlayer)
// m_flDuckTime = 262 (linux diff +5 = 267)
#define OFFSET_DUCKTIME     262
#define OFFSET_FOV          363
#define EXTRAOFFSET_PLAYER  5

// Weapon Offsets (CBasePlayerWeapon)
// m_fInReload = 54 (linux diff +4 = 58)
#define OFFSET_WEAPON_IN_RELOAD 54
#define EXTRAOFFSET_WEAPON      4

#define DEFAULT_FOV 90

new g_pcvar_enable
new g_pcvar_debug

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_cvar("gameland_fastduck_fix_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY)

    g_pcvar_enable = register_cvar("gl_fastduck_fix", "1")
    g_pcvar_debug  = register_cvar("gl_fastduck_debug", "0")

    RegisterHam(Ham_Player_PreThink, "player", "ham_player_prethink", 0)
    RegisterHam(Ham_Spawn, "player", "ham_player_spawn_post", 1)

    // PERMANENT FIX FOR GOLDSRC FAMAS RELOAD BURST-MODE SWITCH BUG:
    // In GoldSrc/Counter-Strike 1.6 engine, CFamas::Reload() was copied from scoped weapons
    // (AUG/SG552) and erroneously calls SecondaryAttack() if m_iFOV != DEFAULT_FOV (90).
    // By intercepting SecondaryAttack on weapon_famas while m_fInReload is active,
    // we block the engine bug completely while keeping manual right-click fire-mode toggles intact.
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_famas", "ham_famas_secondary_attack_pre", 0)
}

public ham_player_spawn_post(id)
{
    if (is_user_alive(id))
    {
        // Sanitize player FOV in case it was corrupted or 0
        new fov = get_pdata_int(id, OFFSET_FOV, EXTRAOFFSET_PLAYER)
        if (fov <= 0)
        {
            set_pdata_int(id, OFFSET_FOV, DEFAULT_FOV, EXTRAOFFSET_PLAYER)
        }
    }
}

public ham_famas_secondary_attack_pre(weapon)
{
    if (!pev_valid(weapon))
        return HAM_IGNORED

    // If weapon is currently reloading, NEVER allow SecondaryAttack to toggle burst mode!
    if (get_pdata_int(weapon, OFFSET_WEAPON_IN_RELOAD, EXTRAOFFSET_WEAPON))
    {
        return HAM_SUPERCEDE
    }

    return HAM_IGNORED
}

public ham_player_prethink(id)
{
    if (!get_pcvar_num(g_pcvar_enable) || !is_user_alive(id) || is_user_bot(id))
        return HAM_IGNORED

    // Sanitize FOV if ever zero
    new fov = get_pdata_int(id, OFFSET_FOV, EXTRAOFFSET_PLAYER)
    if (fov <= 0)
    {
        set_pdata_int(id, OFFSET_FOV, DEFAULT_FOV, EXTRAOFFSET_PLAYER)
    }

    // CRITICAL FIX: If player is holding a sniper rifle (AWP, Scout, G3SG1, SG550) or aiming/shooting,
    // NEVER touch duck offsets or movement delays!
    new clip, ammo
    new weapon = get_user_weapon(id, clip, ammo)
    if (weapon == CSW_AWP || weapon == CSW_SCOUT || weapon == CSW_G3SG1 || weapon == CSW_SG550)
        return HAM_IGNORED

    new button = pev(id, pev_button)
    new oldbuttons = pev(id, pev_oldbuttons)

    // Also ignore if player is currently firing or using secondary attack (zooming/scoping)
    if ((button & IN_ATTACK) || (button & IN_ATTACK2) || (oldbuttons & IN_ATTACK) || (oldbuttons & IN_ATTACK2))
        return HAM_IGNORED

    new flags = pev(id, pev_flags)

    // Player released duck key while on ground
    if ((oldbuttons & IN_DUCK) && !(button & IN_DUCK) && (flags & FL_ONGROUND))
    {
        // When tapping duck (Fast Duck / Double Duck), the engine introduces a delay penalty in m_flDuckTime
        new Float:ducktime = get_pdata_float(id, OFFSET_DUCKTIME, EXTRAOFFSET_PLAYER)
        if (ducktime > 0.0)
        {
            // Reset the delay penalty immediately to keep the movement fluid and synchronized with hitbox
            set_pdata_float(id, OFFSET_DUCKTIME, 0.0, EXTRAOFFSET_PLAYER)

            if (get_pcvar_num(g_pcvar_debug))
                server_print("[GL DUCK] Cleared duck penalty for player %d", id)
        }
    }

    return HAM_IGNORED
}
