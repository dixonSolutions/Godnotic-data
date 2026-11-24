#include "touch_weapons.qh"
#include "touch_init.qh"

// Well past any real inventory: the stock panel registers every weapon in the
// registry, owned or not, and a 16-slot table silently dropped the last rows.
const int TOUCH_WEAP_SLOTS = 64;
// Sideways forgiveness (and upwards over the first row), of a row's height.
const float TOUCH_WEAP_FORGIVE = 0.12;

int touch_weap_count;
vector touch_weap_pos[TOUCH_WEAP_SLOTS];
vector touch_weap_size[TOUCH_WEAP_SLOTS];
float touch_weap_impulse[TOUCH_WEAP_SLOTS];
bool touch_weap_owned[TOUCH_WEAP_SLOTS];

// The strip's resize grip, as last drawn (Touch_Weapons_SetGrip).
bool touch_weap_grip;
vector touch_weap_grip_pos;
vector touch_weap_grip_size;
float touch_weap_grip_u;
int touch_weap_grip_rows;
// The HOOK entry and the NADE row, as last drawn (Touch_Weapons_SetHook/Nade).
bool touch_weap_hook_row;
bool touch_weap_hook_press;
vector touch_weap_hook_pos;
vector touch_weap_hook_size;
bool touch_weap_nade_row;
bool touch_weap_nade;
vector touch_weap_nade_pos;
vector touch_weap_nade_size;
float touch_weap_nade_gap;

// When the slots were built, and when the overlay last drew. Input runs before
// the HUD each frame, so it reads the slots the previous frame drew; if that
// frame drew no strip (dead, observing, hidden), the slots are left over from
// some earlier frame and must not take a tap on a strip that is not there.
float touch_weap_built = -1;
float touch_weap_frame = -2;

float Touch_Weapons_Now(void)
{
	return gettime(GETTIME_FRAMESTART);
}

void Touch_Weapons_MarkFrame(void)
{
	touch_weap_frame = Touch_Weapons_Now();
}

bool Touch_Weapons_Fresh(void)
{
	return touch_weap_built == touch_weap_frame;
}

void Touch_Weapons_BeginFrame(void)
{
	touch_weap_count = 0;
	touch_weap_grip = false;
	touch_weap_nade = false;
	touch_weap_nade_row = false;
	touch_weap_hook_row = false;
	touch_weap_hook_press = false;
	touch_weap_built = Touch_Weapons_Now();
}

// Registered whether or not the controls are up: with a keyboard attached the
// strip is still a switcher for a finger (Touch_DeskActive). Nothing reads the
// table unless a finger is being placed.
void Touch_Weapons_AddSlot(vector pos, vector size, float impulse, bool owned)
{
	if (touch_weap_count >= TOUCH_WEAP_SLOTS)
		return;
	if (size.x < 2 || size.y < 2)
		return;
	int i = touch_weap_count;
	touch_weap_pos[i] = pos;
	touch_weap_size[i] = size;
	touch_weap_impulse[i] = impulse;
	touch_weap_owned[i] = owned;
	touch_weap_count += 1;
}

void Touch_Weapons_SetGrip(vector pos, vector size, float u, int rows)
{
	touch_weap_grip = true;
	touch_weap_grip_pos = pos;
	touch_weap_grip_size = size;
	touch_weap_grip_u = u;
	touch_weap_grip_rows = rows;
}

void Touch_Weapons_SetHook(vector pos, vector size, bool pressable)
{
	touch_weap_hook_row = true;
	touch_weap_hook_press = pressable;
	touch_weap_hook_pos = pos;
	touch_weap_hook_size = size;
}

// The NADE row takes a finger while there is a grenade to throw or one cooking;
// the gap above it (gap high) is dead.
void Touch_Weapons_SetNade(vector pos, vector size, bool pressable, float gap)
{
	touch_weap_nade_row = true;
	touch_weap_nade = pressable;
	touch_weap_nade_pos = pos;
	touch_weap_nade_size = size;
	touch_weap_nade_gap = gap;
}

// One band per finger, no padding up or down into the next row (sideways only):
// the old rule padded every row on all four sides and tested NADE only while a
// grenade was ready, so a finger on the waiting NADE row's top edge landed in
// the pad of the row above, and with the Hook weapon there that was the hook.
int Touch_Weapons_ActionKind(vector p)
{
	if (!Touch_Weapons_Fresh())
		return TOUCH_WEAP_ACT_NONE;
	if (touch_weap_hook_row)
	{
		vector o = touch_weap_hook_pos;
		vector s = touch_weap_hook_size;
		float pad = s.y * TOUCH_WEAP_FORGIVE;
		if (p.x >= o.x - pad && p.x <= o.x + s.x + pad && p.y >= o.y && p.y < o.y + s.y)
			return touch_weap_hook_press ? TOUCH_WEAP_ACT_HOOK : TOUCH_WEAP_ACT_DEAD;
	}
	if (touch_weap_nade_row)
	{
		vector o = touch_weap_nade_pos;
		vector s = touch_weap_nade_size;
		float pad = s.y * TOUCH_WEAP_FORGIVE;
		if (p.x >= o.x - pad && p.x <= o.x + s.x + pad && p.y >= o.y - touch_weap_nade_gap && p.y < o.y + s.y)
			return (touch_weap_nade && p.y >= o.y) ? TOUCH_WEAP_ACT_NADE : TOUCH_WEAP_ACT_DEAD;
	}
	return TOUCH_WEAP_ACT_NONE;
}

bool Touch_Weapons_GripHit(vector p)
{
	if (!touch_weap_grip || !Touch_Weapons_Fresh())
		return false;
	vector o = touch_weap_grip_pos;
	vector s = touch_weap_grip_size;
	return p.x >= o.x && p.x <= o.x + s.x && p.y >= o.y && p.y <= o.y + s.y;
}

float Touch_Weapons_GripU(void)
{
	return touch_weap_grip_u;
}

int Touch_Weapons_GripRows(void)
{
	return touch_weap_grip_rows;
}

bool Touch_Weapons_Hit(vector p)
{
	return Touch_Weapons_HitImpulse(p) >= 0;
}

float Touch_Weapons_HitImpulse(vector p)
{
	if (!Touch_Weapons_Fresh())
		return -1;
	int i;
	for (i = 0; i < touch_weap_count; ++i)
	{
		vector o = touch_weap_pos[i];
		vector s = touch_weap_size[i];
		// Forgiving sideways, and upwards over the first row; between rows the
		// bands share their edges (no pad into the row above or below).
		float pad = s.y * TOUCH_WEAP_FORGIVE;
		float top = o.y - (i == 0 ? pad : 0);
		if (p.x >= o.x - pad && p.x <= o.x + s.x + pad && p.y >= top && p.y < o.y + s.y)
		{
			if (!touch_weap_owned[i])
				return -1;
			return touch_weap_impulse[i];
		}
	}
	return -1;
}

void Touch_Weapons_SelectImpulse(float impulse)
{
	if (impulse < 0)
		return;
	// Same path as number keys / weapon_group_N
	localcmd("impulse ", ftos(impulse), "\n");
}
