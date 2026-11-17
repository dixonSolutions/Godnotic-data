#include "dialog_touch_join.qh"

#include "touch_menu_scale.qh"
#include "checkbox.qh"

bool TouchJoin_Watching()
{
	string m = cvar_string("_touch_hud_mode");
	return m == "spectating" || m == "following";
}

void GodnoticTeamButton_draw(entity me)
{
	if (me.disabled)
		return;
	SUPER(GodnoticTeamButton).draw(me);
}

entity makeGodnoticTeamButton(string theText, vector theColor, string theCommand)
{
	entity me = NEW(GodnoticTeamButton);
	me.configureXonoticCommandButton(me, theText, theColor, theCommand, COMMANDBUTTON_CLOSE, string_null);
	return me;
}

void GodnoticJoinDialog_configureDialog(entity me)
{
	// rows two units tall: 60 dp buttons with the touch layer's row height
	if (touch_menu_on)
		me.rowHeight = TouchMenuScale_dpToUnits(30 * TouchMenuScale_size());
	SUPER(GodnoticJoinDialog).configureDialog(me);
}

void GodnoticJoinDialog_showNotify(entity me)
{
	SUPER(GodnoticJoinDialog).showNotify(me);
	float teams = cvar("_teams_available");
	bool teamgame = (cvar("_touch_hud_flags") & 4) || teams;
	if (me.team1) me.team1.disabled = !(teams & 1);
	if (me.team2) me.team2.disabled = !(teams & 2);
	if (me.team3) me.team3.disabled = !(teams & 4);
	if (me.team4) me.team4.disabled = !(teams & 8);
	if (me.autoButton)
		me.autoButton.setText(me.autoButton, (teamgame ? _("Join (auto-select team)") : _("Join")));
	me.wasWatching = TouchJoin_Watching();
}

// Closes itself once the player is in the game (a choice here, the server's
// own auto-join, another way in): it was up to get them there.
void GodnoticJoinDialog_draw(entity me)
{
	if (me.wasWatching && cvar_string("_touch_hud_mode") == "playing")
	{
		me.wasWatching = false;
		me.close(me);
		return;
	}
	SUPER(GodnoticJoinDialog).draw(me);
}

void GodnoticJoinDialog_fill(entity me)
{
	float teams = cvar("_teams_available");
	int n = 1;
	float w;
	if (teams & 1) n++;
	if (teams & 2) n++;
	if (teams & 4) n++;
	if (teams & 8) n++;
	w = 4.0 / n;
	// the title and the auto-join setting, side by side
	me.gotoRC(me, 0, 0);
		me.TD(me, 1, 2.4, makeXonoticTextLabel(0, _("Game")));
		me.TD(me, 1, 1.6, makeXonoticCheckBox(0, "touch_always_autojoin", _("Auto-join")));
	// one row, every button the same width
	me.gotoRC(me, 1, 0);
	me.autoButton = NULL;
	if (teams & 1) me.TD(me, 2, w, me.team1 = makeGodnoticTeamButton(_("Red"), '1 0.5 0.5', "touch_join red"));
	if (teams & 2) me.TD(me, 2, w, me.team2 = makeGodnoticTeamButton(_("Blue"), '0.5 0.5 1', "touch_join blue"));
	if (teams & 4) me.TD(me, 2, w, me.team3 = makeGodnoticTeamButton(_("Yellow"), '1 1 0.5', "touch_join yellow"));
	if (teams & 8) me.TD(me, 2, w, me.team4 = makeGodnoticTeamButton(_("Pink"), '1 0.5 1', "touch_join pink"));
	if (!teams)
	{
		entity e;
		me.TD(me, 2, w, e = me.autoButton = makeGodnoticCommandButton(_("Join"), '0 0 0', "touch_join auto", COMMANDBUTTON_CLOSE));
		e.preferredFocusPriority = 1;
	}
	me.TD(me, 2, w, makeGodnoticCommandButton(_("Spectate"), '0 0 0', "touch_join spectate", COMMANDBUTTON_CLOSE));
}
