// SPDX-License-Identifier: GPL-3.0-or-later
#include "dialog_touch_votecall.qh"

#include "touchbutton.qh"
#include "touch_menu_scale.qh"
#include "textlabel.qh"
#include "inputbox.qh"
#include "util.qh"

entity touch_vote_map_input;

bool TouchVoteCall_ValidMap(string map)
{
	if (map == "")
		return false;
	for (int i = 0; i < strlen(map); ++i)
		if (strstrofs("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-", substring(map, i, 1), 0) < 0)
			return false;
	return true;
}

void TouchVoteCall_Map(entity button, entity input)
{
	string map = input.text;
	if (!TouchVoteCall_ValidMap(map))
		return;
	localcmd("cmd vote call gotomap ", map, "\ntogglemenu 0\n");
}

void GodnoticVoteCallDialog_configureDialog(entity me)
{
	// as the game menu: finger-sized rows on a touchscreen
	if (touch_menu_on)
		me.rowHeight = TouchMenuScale_dpToUnits(30 * TouchMenuScale_size());
	SUPER(GodnoticVoteCallDialog).configureDialog(me);
}

// The vote goes to the server with "cmd vote call"; the dialog closes so the
// vote panel and its Yes / No buttons are on screen.
void GodnoticVoteCallDialog_fill(entity me)
{
	entity e;
	me.TR(me);
		me.TD(me, 1.5, 2, e = makeGodnoticButton(_("Back"), '0 0 0'));
			e.onClick = Dialog_Close;
			e.onClickEntity = me;
	me.TR(me);
	me.TR(me);
		me.TD(me, 1.5, 1, e = makeGodnoticCommandButton(_("Restart match"), '0 0 0', "cmd vote call restart; togglemenu 0", COMMANDBUTTON_CLOSE));
		me.TD(me, 1.5, 1, e = makeGodnoticCommandButton(_("End match"), '0 0 0', "cmd vote call endmatch; togglemenu 0", COMMANDBUTTON_CLOSE));
	me.TR(me);
	me.TR(me);
		me.TD(me, 1.5, 1, e = makeGodnoticCommandButton(_("More time"), '0 0 0', "cmd vote call extendmatchtime; togglemenu 0", COMMANDBUTTON_CLOSE));
		me.TD(me, 1.5, 1, e = makeGodnoticCommandButton(_("Next map"), '0 0 0', "cmd vote call nextmap; togglemenu 0", COMMANDBUTTON_CLOSE));
	me.TR(me);
	me.TR(me);
		me.TD(me, 1, 2, e = makeXonoticTextLabel(0, _("Change to map (name, e.g. dance):")));
	me.TR(me);
		me.TD(me, 1.3, 2, touch_vote_map_input = makeXonoticInputBox(0, string_null));
			touch_vote_map_input.allowedCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-";
	me.TR(me);
	me.TR(me);
		me.TD(me, 1.5, 2, e = makeGodnoticButton(_("Vote for this map"), '0 0 0'));
			e.onClick = TouchVoteCall_Map;
			e.onClickEntity = touch_vote_map_input;
	me.TR(me);
	me.TR(me);
		// what else the server accepts: printed to the console
		me.TD(me, 1.5, 2, e = makeGodnoticCommandButton(_("List all vote commands"), '0 0 0', "cmd vote help; togglemenu 0; toggleconsole", 0));
}

void TouchVoteCall_ConfigureDialogs(entity mainwindow)
{
	entity dialog = NEW(GodnoticVoteCallDialog);
	dialog.configureDialog(dialog);
	mainwindow.addItemCentered(mainwindow, dialog, dialog.intendedWidth * eX + dialog.intendedHeight * eY, SKINALPHAS_MAINMENU_z);
}
