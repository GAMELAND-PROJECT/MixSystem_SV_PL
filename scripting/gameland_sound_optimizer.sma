#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>

#define PLUGIN  "GameLand Sound & C4 Audio Fixer"
#define VERSION "1.2.0"
#define AUTHOR  "GAMELAND"

#define MAX_PLAYERS 32

new g_pcvar_enable
new g_pcvar_footstep_boost
new g_pcvar_footstep_enemy_boost
new g_pcvar_footstep_vol
new g_pcvar_footstep_atten
new g_pcvar_ladder_boost
new g_pcvar_ambient_clean
new g_pcvar_ambient_volume
new g_pcvar_anti_silent_plant
new g_pcvar_anti_silent_defuse
new g_pcvar_debug

new g_cleanAmbientEntCount = 0

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_cvar("gameland_sound_optimizer_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY)

    g_pcvar_enable = register_cvar("gl_snd_optimizer", "1")
    g_pcvar_footstep_boost = register_cvar("gl_snd_footstep_boost", "1")
    g_pcvar_footstep_enemy_boost = register_cvar("gl_snd_enemy_priority", "1")
    g_pcvar_footstep_vol = register_cvar("gl_snd_footstep_vol", "1.0")          // Crystal clear volume (0.1 - 1.0)
    g_pcvar_footstep_atten = register_cvar("gl_snd_footstep_atten", "1.0")      // ATTN_NORM (1.0) maintains accurate vertical 3D depth in de_nuke
    g_pcvar_ladder_boost = register_cvar("gl_snd_ladder_boost", "1")
    g_pcvar_ambient_clean = register_cvar("gl_snd_ambient_clean", "1")
    g_pcvar_ambient_volume = register_cvar("gl_snd_ambient_volume", "0.35")     // Calms down deafening map background hums
    g_pcvar_anti_silent_plant = register_cvar("gl_snd_anti_silent_plant", "1")  // Fixes C4 silent planting exploit
    g_pcvar_anti_silent_defuse = register_cvar("gl_snd_anti_silent_defuse", "1")// Fixes silent defusal glitch
    g_pcvar_debug = register_cvar("gl_snd_debug", "0")

    register_forward(FM_EmitSound, "forward_emit_sound")
    register_forward(FM_EmitAmbientSound, "forward_emit_ambient_sound")

    // Event hooks for competitive C4 planting and defusing sound integrity
    register_event("BarTime", "event_bartime", "be", "1>0") // Player begins planting or defusing
    register_concmd("gl_sound_status", "cmd_status", ADMIN_ALL, "- shows GameLand Sound Optimizer status")
}

public plugin_cfg()
{
    if (get_pcvar_num(g_pcvar_enable) && get_pcvar_num(g_pcvar_ambient_clean))
    {
        clean_heavy_ambient_entities()
    }
}

public event_bartime(id)
{
    if (!get_pcvar_num(g_pcvar_enable) || !is_user_alive(id))
        return

    new duration = read_data(1)

    // C4 Planting (usually 3 seconds)
    if (duration == 3 && get_pcvar_num(g_pcvar_anti_silent_plant))
    {
        new team = get_user_team(id)
        if (team == 1) // Terrorist
        {
            // Guarantee audible button arming sound if silent plant bug is attempted
            emit_sound(id, CHAN_ITEM, "weapons/c4_arm.wav", 0.85, ATTN_NORM, 0, PITCH_NORM)
        }
    }
    // C4 Defusing (5 or 10 seconds)
    else if ((duration == 5 || duration == 10) && get_pcvar_num(g_pcvar_anti_silent_defuse))
    {
        new team = get_user_team(id)
        if (team == 2) // CT
        {
            emit_sound(id, CHAN_ITEM, "weapons/c4_disarm.wav", 0.85, ATTN_NORM, 0, PITCH_NORM)
        }
    }
}

public forward_emit_sound(ent, channel, const sample[], Float:volume, Float:attn, flags, pitch)
{
    if (!get_pcvar_num(g_pcvar_enable))
        return FMRES_IGNORED

    // Detect footstep sounds
    if (is_valid_player(ent) && is_user_alive(ent))
    {
        new bool:is_step = false
        new bool:is_ladder = false

        if (sample[0] == 'p' && sample[7] == 'p' && sample[8] == 'l' && sample[9] == '_') // player/pl_
        {
            if (containi(sample, "step") != -1 ||
                containi(sample, "dirt") != -1 ||
                containi(sample, "duct") != -1 ||
                containi(sample, "metal") != -1 ||
                containi(sample, "slosh") != -1 ||
                containi(sample, "tile") != -1 ||
                containi(sample, "wood") != -1 ||
                containi(sample, "snow") != -1 ||
                containi(sample, "grate") != -1)
            {
                is_step = true
            }
            else if (containi(sample, "ladder") != -1)
            {
                is_ladder = true
            }
        }

        if (is_step || is_ladder)
        {
            if (is_ladder && !get_pcvar_num(g_pcvar_ladder_boost))
                return FMRES_IGNORED

            if (!get_pcvar_num(g_pcvar_footstep_boost))
                return FMRES_IGNORED

            new Float:target_vol = get_pcvar_float(g_pcvar_footstep_vol)
            // On multi-level vertical maps like de_nuke, overly aggressive attenuation (0.85) flattens 3D height cues,
            // making upstairs footsteps sound like they are right next to you downstairs.
            // Using ATTN_NORM (1.0) preserves GoldSrc 3D distance and vertical HRTF separation accurately.
            new Float:target_atten = get_pcvar_float(g_pcvar_footstep_atten)
            if (target_atten < 0.95) target_atten = 0.95 // Keep natural vertical drop-off
            if (target_atten > 1.5) target_atten = 1.5

            // Resend with boost and natural 3D attenuation
            forward_return(FMV_CELL, 1)
            engfunc(EngFunc_EmitSound, ent, channel, sample, target_vol, target_atten, flags, pitch)

            if (get_pcvar_num(g_pcvar_debug))
                server_print("[GL SOUND] Optimized step: ent=%d sound=%s vol=%.2f atten=%.2f", ent, sample, target_vol, target_atten)

            return FMRES_SUPERCEDE
        }
    }

    return FMRES_IGNORED
}

public forward_emit_ambient_sound(ent, Float:pos[3], const sample[], Float:vol, Float:attn, flags, pitch)
{
    if (!get_pcvar_num(g_pcvar_enable) || !get_pcvar_num(g_pcvar_ambient_clean))
        return FMRES_IGNORED

    new Float:max_ambient = get_pcvar_float(g_pcvar_ambient_volume)
    if (vol > max_ambient)
    {
        forward_return(FMV_CELL, 1)
        engfunc(EngFunc_EmitAmbientSound, ent, pos, sample, max_ambient, attn, flags, pitch)
        return FMRES_SUPERCEDE
    }

    return FMRES_IGNORED
}

// Clean repetitive, deafening map ambient entities that drown out footstep cues
stock clean_heavy_ambient_entities()
{
    g_cleanAmbientEntCount = 0
    new ent = -1
    new targetname[32]
    new sample[64]

    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ambient_generic")) > 0)
    {
        if (!pev_valid(ent))
            continue

        pev(ent, pev_targetname, targetname, charsmax(targetname))
        pev(ent, pev_message, sample, charsmax(sample))

        // Suppress continuous loud buzzing/wind/water noise generators
        if (containi(sample, "fan") != -1 ||
            containi(sample, "generator") != -1 ||
            containi(sample, "steam") != -1 ||
            containi(sample, "wind") != -1 ||
            containi(sample, "waterfall") != -1 ||
            containi(sample, "siren") != -1 ||
            containi(sample, "car") != -1)
        {
            // Lower their volume to 20% or make quiet
            set_pev(ent, pev_health, 2.0)
            g_cleanAmbientEntCount++
        }
    }

    if (get_pcvar_num(g_pcvar_debug))
        server_print("[GL SOUND] Controlled %d loud ambient sound entities.", g_cleanAmbientEntCount)
}

public cmd_status(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED

    console_print(id, "[GL SOUND] %s v%s by %s", PLUGIN, VERSION, AUTHOR)
    console_print(id, "[GL SOUND] Enabled=%d FootstepBoost=%d LadderBoost=%d",
        get_pcvar_num(g_pcvar_enable),
        get_pcvar_num(g_pcvar_footstep_boost),
        get_pcvar_num(g_pcvar_ladder_boost))
    console_print(id, "[GL SOUND] FootstepVol=%.2f Atten=%.2f EnemyPriority=%d",
        get_pcvar_float(g_pcvar_footstep_vol),
        get_pcvar_float(g_pcvar_footstep_atten),
        get_pcvar_num(g_pcvar_footstep_enemy_boost))
    console_print(id, "[GL SOUND] AmbientClean=%d AmbientVol=%.2f AmbientEntsMuted=%d",
        get_pcvar_num(g_pcvar_ambient_clean),
        get_pcvar_float(g_pcvar_ambient_volume),
        g_cleanAmbientEntCount)
    console_print(id, "[GL SOUND] AntiSilentPlant=%d AntiSilentDefuse=%d",
        get_pcvar_num(g_pcvar_anti_silent_plant),
        get_pcvar_num(g_pcvar_anti_silent_defuse))

    return PLUGIN_HANDLED
}

stock bool:is_valid_player(id)
{
    return (id >= 1 && id <= MAX_PLAYERS)
}
