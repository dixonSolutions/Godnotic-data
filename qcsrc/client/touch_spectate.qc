#include "touch_spectate.qh"
#include "touch_feel.qh"

#include <client/touch_defs.qh>
#include <client/main.qh>
#include <client/touch_draw.qh>
#include <client/touch_input.qh>
#include <client/touch_layout.qh>
#include <client/touch_mode.qh>
#include <client/touch_theme.qh>
#include <client/touch_widget.qh>

// ---------------------------------------------------------------------------
// Spectating, stripped to what a spectator uses (engine/darkplaces/
// touch_spectate.h is the table both HUDs follow): the move stick and the
// UP / DOWN rocker while free-flying, and one bar, previous | follow or free |
// next, bottom right. The server's spectator code reads +attack as "follow" /
// "next player", weapprev as "previous player", +attack2 as "back to free-fly",
// +moveup / +movedown as flying, and +jump as "join": nothing here sends
// +jump. Joining is the swipe handle at the bottom middle, which the engine
// draws and reads under every CSQC (touch_hud.c).
// ---------------------------------------------------------------------------

bool touch_spec_up_held, touch_spec_down_held;
bool touch_spec_key_up, touch_spec_key_down;

int Touch_Spec_State(void)
{
	switch (Touch_Mode())
	{
		case TOUCHMODE_OBSERVING: return TOUCH_SPEC_OBSERVING;
		case TOUCHMODE_FOLLOWING: return TOUCH_SPEC_FOLLOWING;
		case TOUCHMODE_OUT: return TOUCH_SPEC_OUT;
		case TOUCHMODE_OUT_FREE: return TOUCH_SPEC_OUT_FREE;
		default: return TOUCH_SPEC_NONE;
	}
}

bool Touch_Spec_BarShown(int st)
{
	return st != TOUCH_SPEC_NONE;
}

// Free-flying: the stick, UP and DOWN fly the camera.
bool Touch_Spec_Flying(int st)
{
	return st == TOUCH_SPEC_OBSERVING || st == TOUCH_SPEC_OUT_FREE;
}

// TouchSpec_BarAction
int Touch_Spec_BarAction(int st, int part)
{
	if (part == TOUCH_SPEC_BAR_JOIN)
		return st != TOUCH_SPEC_NONE ? TOUCH_SPEC_ACT_JOIN : TOUCH_SPEC_ACT_NONE;
	if (Touch_Spec_Flying(st))
		return TOUCH_SPEC_ACT_FOLLOW;
	if (st == TOUCH_SPEC_FOLLOWING)
		return part == TOUCH_SPEC_BAR_PREV ? TOUCH_SPEC_ACT_PREV : part == TOUCH_SPEC_BAR_MAIN ? TOUCH_SPEC_ACT_FREE : TOUCH_SPEC_ACT_NEXT;
	if (st == TOUCH_SPEC_OUT)
		return part == TOUCH_SPEC_BAR_PREV ? TOUCH_SPEC_ACT_PREV : part == TOUCH_SPEC_BAR_MAIN ? TOUCH_SPEC_ACT_NONE : TOUCH_SPEC_ACT_NEXT;
	return TOUCH_SPEC_ACT_NONE;
}

string Touch_Spec_BarLabel(int st, int part)
{
	int act = Touch_Spec_BarAction(st, part);
	if (part == TOUCH_SPEC_BAR_JOIN)
		return act == TOUCH_SPEC_ACT_JOIN ? "JOIN" : "";
	if (act == TOUCH_SPEC_ACT_NONE)
		return (part == TOUCH_SPEC_BAR_MAIN && st != TOUCH_SPEC_NONE) ? "WATCHING" : "";
	if (part == TOUCH_SPEC_BAR_PREV)
		return "<";
	if (part == TOUCH_SPEC_BAR_NEXT)
		return ">";
	return "FREE";
}

// The bar, fitted like touch_spectate.h TouchSpec_BarLayout: all four parts
// (previous, main, next, JOIN) in one row, moved and shrunk uniformly until
// they fit, so JOIN is never pushed off the right edge.
float touch_spec_bar_hy, touch_spec_bar_left, touch_spec_bar_cy;
void Touch_Spec_BarFit()
{
	float u = Touch_DpUnits();
	float margin = 8 * u;
	float hy = max(TOUCHDP_SECONDARY * 0.5 * u,
		Touch_ScreenMin() * cvar_or("touch_specbar_size", 0.085) * 0.5 * Touch_WidgetScale());
	float w = vid_conwidth, h = vid_conheight;
	float total = 11.45;
	float scale = 1;
	vector c = Touch_WidgetCenter(cvar_or("touch_specbar_x", 0.815), cvar_or("touch_specbar_y", 0.885), 0);
	if (margin * 2 >= w) margin = 0;
	if (margin * 2 >= h) margin = 0;
	if (2 * hy > h - 2 * margin) scale = (h - 2 * margin) / (2 * hy);
	if (total * hy * scale > w - 2 * margin) scale = (w - 2 * margin) / (total * hy);
	hy *= scale;
	total *= hy;
	touch_spec_bar_left = c.x - total * 0.5;
	if (touch_spec_bar_left < margin) touch_spec_bar_left = margin;
	if (touch_spec_bar_left + total > w - margin) touch_spec_bar_left = w - margin - total;
	if (touch_spec_bar_left < 0) touch_spec_bar_left = 0;
	touch_spec_bar_cy = c.y;
	if (touch_spec_bar_cy - hy < margin) touch_spec_bar_cy = margin + hy;
	if (touch_spec_bar_cy + hy > h - margin) touch_spec_bar_cy = h - margin - hy;
	touch_spec_bar_hy = hy;
}

vector Touch_Spec_BarHalf(int part)
{
	touch_spec_bar_hy = 0;
	Touch_Spec_BarFit();
	if (part == TOUCH_SPEC_BAR_MAIN)
		return eX * (touch_spec_bar_hy * 2.2) + eY * touch_spec_bar_hy;
	if (part == TOUCH_SPEC_BAR_JOIN)
		return eX * (touch_spec_bar_hy * 1.15) + eY * touch_spec_bar_hy;
	return eX * touch_spec_bar_hy + eY * touch_spec_bar_hy;
}

vector Touch_Spec_BarCenter(int part)
{
	float x, gap;
	touch_spec_bar_hy = 0;
	Touch_Spec_BarFit();
	gap = 0.25 * touch_spec_bar_hy;
	x = touch_spec_bar_left;
	if (part == TOUCH_SPEC_BAR_PREV)
		return eX * (x + touch_spec_bar_hy) + eY * touch_spec_bar_cy;
	x += 2 * touch_spec_bar_hy + gap;
	if (part == TOUCH_SPEC_BAR_MAIN)
		return eX * (x + 2.2 * touch_spec_bar_hy) + eY * touch_spec_bar_cy;
	x += 4.4 * touch_spec_bar_hy + gap;
	if (part == TOUCH_SPEC_BAR_NEXT)
		return eX * (x + touch_spec_bar_hy) + eY * touch_spec_bar_cy;
	x += 2 * touch_spec_bar_hy + gap;
	return eX * (x + 1.15 * touch_spec_bar_hy) + eY * touch_spec_bar_cy;
}
// The fly rocker: UP over DOWN, beside the stick on its inner side.
vector Touch_Spec_FlyCenter(bool up)
{
	vector m = Touch_WidgetCenter(autocvar_touch_move_x, autocvar_touch_move_y, autocvar_touch_move_size);
	float mr = Touch_StickRadius();
	float r = TOUCHDP_MIN_TARGET * 0.5 * Touch_DpUnits();
	return m + eX * ((autocvar_touch_handedness ? -1 : 1) * (mr + r * 1.6)) + eY * ((up ? -1 : 1) * r * 1.15);
}

float Touch_Spec_FlyRadius(void)
{
	return TOUCHDP_MIN_TARGET * 0.5 * Touch_DpUnits();
}

int Touch_Spec_ActionRole(int act)
{
	switch (act)
	{
		case TOUCH_SPEC_ACT_FOLLOW:
		case TOUCH_SPEC_ACT_NEXT: return TOUCH_ROLE_SPEC_ATTACK;
		case TOUCH_SPEC_ACT_PREV: return TOUCH_ROLE_SPEC_PREV;
		case TOUCH_SPEC_ACT_FREE: return TOUCH_ROLE_SPEC_FREE;
		case TOUCH_SPEC_ACT_JOIN: return TOUCH_ROLE_SPEC_JOIN;
		default: return TOUCH_ROLE_IGNORED;
	}
}

int Touch_Spec_AssignRole(vector p)
{
	int st = Touch_Spec_State();
	if (st == TOUCH_SPEC_NONE || touch_desk)
		return TOUCH_ROLE_NONE;
	if (Touch_InEdgeDeadzone(p))
		return TOUCH_ROLE_IGNORED;
	if (Touch_Spec_BarShown(st))
		for (int part = 0; part < TOUCH_SPEC_BAR_PARTS; ++part)
			if (Touch_HitRectPx(p, Touch_Spec_BarCenter(part), Touch_Spec_BarHalf(part), 1.1))
				return Touch_Spec_ActionRole(Touch_Spec_BarAction(st, part));
	if (Touch_Spec_Flying(st))
	{
		float r = Touch_Spec_FlyRadius() * 1.05;
		if (Touch_PointInCircle(p, Touch_Spec_FlyCenter(true), r))
			return TOUCH_ROLE_SPEC_UP;
		if (Touch_PointInCircle(p, Touch_Spec_FlyCenter(false), r))
			return TOUCH_ROLE_SPEC_DOWN;
		// The stick flies the camera while observing; following, the view is theirs.
		if (!cvar("vid_keyboard_detected") && (Touch_InMoveZone(p)
			|| (autocvar_touch_move_visible && Touch_HitCircle(p, autocvar_touch_move_x, autocvar_touch_move_y, autocvar_touch_move_size, 1.0))))
			return Touch_RoleOwned(TOUCH_ROLE_MOVE) ? TOUCH_ROLE_IGNORED : TOUCH_ROLE_MOVE;
	}
	return cvar("vid_mouse_confirmed") || Touch_RoleOwned(TOUCH_ROLE_LOOK) ? TOUCH_ROLE_IGNORED : TOUCH_ROLE_LOOK;
}

bool Touch_Spec_FingerFrame(int role, bool first)
{
	// a bar turned off under a held finger stops acting at once
	if (!Touch_Spec_BarShown(Touch_Spec_State())
		&& (role == TOUCH_ROLE_SPEC_ATTACK || role == TOUCH_ROLE_SPEC_PREV || role == TOUCH_ROLE_SPEC_FREE || role == TOUCH_ROLE_SPEC_JOIN))
		return false;
	if (role == TOUCH_ROLE_SPEC_ATTACK)
		touch_spec_attack = true;
	else if (role == TOUCH_ROLE_SPEC_FREE)
		touch_spec_attack2 = true;
	else if (role == TOUCH_ROLE_SPEC_UP)
		touch_spec_up_held = true;
	else if (role == TOUCH_ROLE_SPEC_DOWN)
		touch_spec_down_held = true;
	else if (role == TOUCH_ROLE_SPEC_PREV)
	{
		if (first)
			localcmd("weapprev\n");
	}
	else if (role == TOUCH_ROLE_SPEC_JOIN)
	{
		if (first)
			localcmd(cvar_or("touch_join_dialog_auto", 1) ? "touch_join auto\n" : "touch_join_dialog\n");
	}
	else
		return false;
	return true;
}

void Touch_Spec_SetMoveKey(string key, bool down, bool was)
{
	if (down != was)
		localcmd(strcat((down ? "+" : "-"), key, " ", TOUCH_HOLD_KEY, "\n"));
}

void Touch_Spec_Release(void)
{
	Touch_Spec_SetMoveKey("moveup", false, touch_spec_key_up);
	Touch_Spec_SetMoveKey("movedown", false, touch_spec_key_down);
	touch_spec_key_up = false;
	touch_spec_key_down = false;
}

void Touch_Spec_Frame(void)
{
	int st = Touch_Spec_State();
	bool up = touch_spec_up_held && Touch_Spec_Flying(st);
	bool down = touch_spec_down_held && Touch_Spec_Flying(st);
	Touch_Spec_SetMoveKey("moveup", up, touch_spec_key_up);
	Touch_Spec_SetMoveKey("movedown", down, touch_spec_key_down);
	touch_spec_key_up = up;
	touch_spec_key_down = down;
	// Never +jump: that is the join, the engine's swipe handle alone.
	touch_spec_jump = false;
	touch_spec_up_held = false;
	touch_spec_down_held = false;
}

bool Touch_Spec_DrawOverlay(float alpha)
{
	int st = Touch_Spec_State();
	if (st == TOUCH_SPEC_NONE || cvar("_touch_join_waiting"))
		return false;
	if (Touch_Spec_Flying(st))
	{
		if (autocvar_touch_move_visible && !cvar("vid_keyboard_detected"))
			Touch_DrawMoveStick(alpha);
		float r = Touch_Spec_FlyRadius();
		Touch_Widget_Button(Touch_Spec_FlyCenter(true), r, "UP", touch_spec_key_up, alpha * 0.9, TOUCH_C_ACCENT);
		Touch_Widget_Button(Touch_Spec_FlyCenter(false), r, "DOWN", touch_spec_key_down, alpha * 0.9, TOUCH_C_ACCENT);
	}
	for (int part = 0; Touch_Spec_BarShown(st) && part < TOUCH_SPEC_BAR_PARTS; ++part)
	{
		string label = Touch_Spec_BarLabel(st, part);
		if (label == "")
			continue;
		int act = Touch_Spec_BarAction(st, part);
		bool held = Touch_RoleOwned(Touch_Spec_ActionRole(act)) && act != TOUCH_SPEC_ACT_NONE;
		Touch_Widget_Capsule(Touch_Spec_BarCenter(part), Touch_Spec_BarHalf(part), label, held || (part == TOUCH_SPEC_BAR_MAIN && Touch_Spec_Flying(st)), false,
			(act == TOUCH_SPEC_ACT_NONE ? alpha * 0.6 : alpha), TOUCH_C_ACCENT);
	}
	// who is being watched, over the bar
	string target = Touch_Spec_BarShown(st) ? Touch_ModeTarget() : "";
	if (target != "")
	{
		vector c = Touch_Spec_BarCenter(TOUCH_SPEC_BAR_MAIN);
		float hy = Touch_Spec_BarHalf(TOUCH_SPEC_BAR_MAIN).y;
		float fs = bound(9, hy * 0.62, 20);
		vector fsz = eX * fs + eY * fs;
		float w = stringwidth(target, false, fsz);
		vector at = c - eY * (hy * 1.75);
		drawfill(at - eX * (w * 0.5 + fs * 0.6) - eY * (fs * 0.75), eX * (w + fs * 1.2) + eY * (fs * 1.5), TOUCH_C_SURFACE, alpha * 0.6, DRAWFLAG_NORMAL);
		drawstring(at - eX * (w * 0.5) - eY * (fs * 0.5), target, fsz, '1 1 1', alpha, DRAWFLAG_NORMAL);
	}
	return true;
}

string Touch_Spec_ObserverHint(string hint, int status, int choice)
{
	if (cvar("_touch_join_waiting"))
		return "";
	if ((cvar("vid_touchscreen") || cvar("vid_touchscreen_detected")) && !cvar("vid_mouse_confirmed") && cvar("vid_keyboard_detected"))
	{
		if (status == -1 && choice == 0)
			return Touch_Spec_BarShown(Touch_Spec_State()) ? "^1Tap ^3>^1 to spectate" : "";
		if (status != -1 && choice == 1)
			return Touch_Spec_State() == TOUCH_SPEC_FOLLOWING ? "^1Tap ^3FREE^1 to observe" : "";
	}
	if ((cvar("vid_touchscreen") || cvar("vid_touchscreen_detected")) && !cvar("vid_keyboard_detected"))
	{
		if (choice == 2 || (status == -1 && choice == 1))
			return "";
		if (status == -1)
			return Touch_Spec_BarShown(Touch_Spec_State()) ? "^1Tap ^3>^1 to spectate" : "";
		if (choice == 1)
			return Touch_Spec_State() == TOUCH_SPEC_FOLLOWING ? "^1Tap ^3FREE^1 to observe" : "";
	}
	return hint;
}

string Touch_Spec_TeamHint(string hint, string color)
{
	// There is no team-selection control in the touch overlay.
	if (cvar("vid_touchscreen"))
		return strcat(color, _("Teams are unbalanced!"));
	return hint;
}

string Touch_Spec_NextHint(string hint, int status, int choice)
{
	if (cvar("_touch_join_waiting"))
		return "";
	if ((!cvar("vid_touchscreen") && !cvar("vid_touchscreen_detected")) || (cvar("vid_keyboard_detected") && cvar("vid_mouse_confirmed")) || status == -1 || choice != 0)
		return hint;
	if (!Touch_Spec_BarShown(Touch_Spec_State()))
		return "";
	return "^1Tap ^3<^1 or ^3>^1 for next or previous player";
}

string Touch_Spec_JoinHint(string hint)
{
	if (cvar("_touch_join_waiting"))
		return "";
	if ((!cvar("vid_touchscreen") && !cvar("vid_touchscreen_detected")) || cvar("vid_keyboard_detected"))
		return hint;
	if (Touch_Spec_BarShown(Touch_Spec_State()))
		return "^1Tap ^3JOIN^1 to join";
	return "^1MENU > ^3Join game^1 to join";
}

string Touch_Spec_CommandLabel(string command)
{
	int st = Touch_Spec_State();
	if (st == TOUCH_SPEC_NONE || !Touch_Active())
		return "";
	if (command == "+jump")
		return (st == TOUCH_SPEC_OBSERVING || st == TOUCH_SPEC_FOLLOWING) ? "MENU" : "";
	if (Touch_Spec_BarShown(st))
	{
		if (command == "+fire" || command == "+attack")
			return Touch_Spec_Flying(st) ? "FREE" : ">";
		// flying, next / previous weapon change the speed: no button for that
		if (command == "weapnext")
			return Touch_Spec_Flying(st) ? "" : ">";
		if (command == "weapprev")
			return Touch_Spec_Flying(st) ? "" : "<";
		if (command == "+fire2")
			return st == TOUCH_SPEC_FOLLOWING ? "FREE" : "";
	}
	return "";
}
