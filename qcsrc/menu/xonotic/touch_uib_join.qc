// SPDX-License-Identifier: GPL-3.0-or-later
#include "touch_uib_touch.qh"
#include "dialog_touch_join.qh"

// Godnotic UI bridge: the join popup. Xonotic's join dialog (auto-select, the
// teams the server offers, spectate) as a description, so a native renderer
// shows it as its own dialog: id "join", a modal in the game context.
// UIB_JoinOpen is what "menu_cmd directmenu TeamSelect" becomes when a native
// renderer draws the menu (TouchGameMenu_Route); the engine sends that for an
// observer when a match starts and from Join game / Change team. Without a
// native renderer the dialog is dialog_touch_join.qc.
// Each button's action is "join.<choice>" and runs "touch_join <choice>".

bool uib_join_watching;   // opened for a player who was watching: closes once they play

void UIB_JoinButton(string key, string label, string action, string style)
{
	UIB_Open(key, "button");
		uib_s("label", label);
		uib_j("action", action);
		uib_s("style", style);
		uib_s("width", "fill");
	UIB_Close();
}

void UIB_BuildJoin()
{
	float teams = cvar("_teams_available");
	bool teamgame = (cvar("_touch_hud_flags") & 4) || teams;
	if (!UIB_Screen("join", ""))
		return;
	uib_s("presentation", "dialog");
	uib_b("dismissable", 1);
	uib_j("header", "{\"hidden\":true}");
	// one row: the title and the auto-join checkbox side by side
	UIB_Open("head", "row");
		uib_s("align", "center");
		UIB_Text("title", _("Game"), "title");
		UIB_Check("autojoin", _("Auto-join"), "cvar:touch_always_autojoin", "");
	UIB_Close();
	// one horizontal row, every button the same width
	UIB_Open("buttons", "row");
		uib_s("align", "center");
		if (teamgame && teams)
		{
			if (teams & 1) UIB_JoinButton("red", _("Red"), UIB_A("join.red", _("Red"), "team"), "team-red");
			if (teams & 2) UIB_JoinButton("blue", _("Blue"), UIB_A("join.blue", _("Blue"), "team"), "team-blue");
			if (teams & 4) UIB_JoinButton("yellow", _("Yellow"), UIB_A("join.yellow", _("Yellow"), "team"), "team-yellow");
			if (teams & 8) UIB_JoinButton("pink", _("Pink"), UIB_A("join.pink", _("Pink"), "team"), "team-pink");
		}
		else
			UIB_JoinButton("join", _("Join"), UIB_A("join.auto", _("Join"), "play"), "primary");
		UIB_JoinButton("spectate", _("Spectate"), UIB_A("join.spectate", _("Spectate"), "esp"), "secondary");
	UIB_Close();
	UIB_Done();
}
bool UIB_JoinUp()
{
	return strstrofs(strcat(" ", uibn_modal, " "), " join ", 0) >= 0;
}

void UIB_JoinClose()
{
	if (UIB_TopScreen() == "join")
	{
		UIB_DropLast(true);
		UIB_Nav();
	}
	// back to the match, not to the pause menu under the popup
	if (uibn_context == "game" && uibn_modal == "")
		m_hide();
}

// True when a bridge renderer shows the menu and the popup is now up.
bool UIB_JoinOpen()
{
	// A native renderer shows it as its own dialog. The QuakeC renderer leaves
	// it to the finger-sized stock dialog (dialog_touch_join.qc), which opens
	// over the bridge menu like the game menu does: its popups sit on the
	// full-screen pause page, and a join question belongs over the match.
	if (!UIB_EngineHasBridge() || !uib_native())
		return false;
	if (!uib_inited)
		UIB_Init();
	UIB_Tick();   // the context may still read "menu" or "loading" right after a join
	// A join preview is the world on screen with the signon still finishing: the
	// question belongs over it, before the player is made an observer.
	bool live = uibn_context == "game" || (uibn_context == "loading" && cvar("_touch_join_preview"));
	if (!uib_inited || !live)
		return false;
	uib_join_watching = TouchJoin_Watching();
	if (!UIB_JoinUp())
		UIB_Modal("join");
	else
		UIB_Build("join");
	if (!Menu_Active)
		m_display();
	return true;
}

bool UIB_JoinAction(string a)
{
	if (a == "join.open")
	{
		localcmd("\ntouch_join_dialog\n");
		return true;
	}
	if (substring(a, 0, 5) != "join." || a == "join.address")
		return false;
	// answered: the popup's Cancel now closes a team question, it does not leave
	cvar_set("_uib_join_cancel", "");
	localcmd(sprintf("\ntouch_join %s\n", substring(a, 5, -1)));
	UIB_JoinClose();
	return true;
}

// Back or a tap outside: as Spectate while watching (the player stays where
// they are), and never the pause menu under the popup.
bool UIB_JoinBack()
{
	if (UIB_TopScreen() != "join")
		return false;
	// a join started from a menu screen and not answered yet: Cancel leaves it and
	// returns there (UIB_ReturnFromGame). Watching a match, it just closes.
	bool cancel_join = cvar_string("_uib_join_cancel") != "";
	// dismissing the question is not a choice: stop hiding the observer HUD
	localcmd("\ntouch_join_cancel\n");
	UIB_JoinClose();
	if (cancel_join)
		localcmd("\ndisconnect\n");
	return true;
}

// The game's Welcome dialog (a newer server's game code opens it on connect:
// the server's name and message, Join! and Spectate) is a stock dialog, which a
// native renderer cannot draw. There the join popup asks instead: the engine
// keeps it owed (no touch_join_answered) and opens it once the player is an
// observer with the screen free, as on any other server.
bool UIB_WelcomeNative()
{
	return UIB_EngineHasBridge() && uib_native();
}

// Every tick: the popup goes once the player is in the game.
void UIB_JoinTick()
{
	if (!UIB_JoinUp())
		return;
	if ((uibn_context != "game" && !cvar("_touch_join_preview"))
		|| (uib_join_watching && cvar_string("_touch_hud_mode") == "playing"))
	{
		uib_join_watching = false;
		UIB_JoinClose();
	}
}
