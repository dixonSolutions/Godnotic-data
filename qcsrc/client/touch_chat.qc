#include "touch_chat.qh"
#include "touch_keyboard.qh"
#include "touch_pointer.qh"
#include "touch_widget.qh"
#include "touch_layout.qh"
#include "touch_init.qh"
#include "touch_defs.qh"
#include "touch_input.qh"
#include <lib/cvar.qh>

const int TOUCH_CHAT_PICK_MAX = 64;   // names held
const int TOUCH_CHAT_PICK_ROWS = 4;   // rows shown; the rest scroll by drag
int touch_chat_pick_off;
bool touch_chat_pick_press;
bool touch_chat_pick_dragged;
float touch_chat_pick_y0;
float touch_chat_pick_vel;      // rows per second left to coast after a flick
float touch_chat_pick_acc;      // part of a row not yet scrolled
float touch_chat_pick_last_y;
float touch_chat_pick_last_t;
float touch_chat_pick_tick;
int touch_chat_pick_n;
string touch_chat_pick_name[TOUCH_CHAT_PICK_MAX];
bool touch_chat_pick_spec[TOUCH_CHAT_PICK_MAX];
int touch_chat_pick_at;
int touch_chat_pick_hot;
string touch_chat_pick_for;

vector Touch_Chat_FieldCenter(void);
vector Touch_Chat_FieldHalf(void);
float Touch_Chat_Pad(void);
vector Touch_Chat_SheetCenter(void);
vector Touch_Chat_InnerHalf(void);

// The backlog scrolls by the pixel, with momentum, and only the rows on screen
// are drawn (the same rules as the engine's chat log box). hist_off is how far the
// content is pulled down from the live state (0: the newest line at the bottom).
float touch_chat_hist_off;
float touch_chat_hist_vel;       // units per second left to coast
bool touch_chat_hist_press;
float touch_chat_hist_last_y;
float touch_chat_hist_last_t;

bool touch_chat_open;
bool touch_chat_team;
string touch_chat_text;
int touch_chat_caret;          // insertion point: a character index into the text
bool touch_chat_field_hot;     // a finger is placing the caret

string touch_chat_line[TOUCH_CHAT_HISTORY];
int touch_chat_count;
int touch_chat_head;

bool touch_chat_pill_arming;
vector touch_chat_pill_down;
int touch_chat_hot_row;
int touch_chat_hot_cell;
int touch_chat_hot_button;
float touch_chat_hot_time;

const int TOUCH_CHAT_BTN_NONE  = -1;
const int TOUCH_CHAT_BTN_CLOSE = 0;
const int TOUCH_CHAT_BTN_COUNT = 1;

void Touch_Chat_Reset(void)
{
	// A reset can land mid-session (map change), and the sheet borrows the chat
	// panel while it is open, so it has to be handed back or the feed stays off.
	if (touch_chat_open)
		cvar_set("hud_panel_chat", "1");
	touch_chat_open = false;
	touch_chat_team = false;
	touch_chat_pill_arming = false;
	touch_chat_hot_row = -1;
	touch_chat_hot_cell = -1;
	touch_chat_hot_button = TOUCH_CHAT_BTN_NONE;
	touch_chat_hist_off = 0;
	touch_chat_hist_vel = 0;
	touch_chat_hist_press = false;
	touch_chat_pick_n = 0;
	touch_chat_pick_hot = -1;
	strcpy(touch_chat_pick_for, "");
	strcpy(touch_chat_text, "");
	touch_chat_caret = 0;
}

// ---------------------------------------------------------------------------
// Backlog
// ---------------------------------------------------------------------------

// The engine routes a print to its chat box when the first byte is \1 (say and
// tell, with a sound) or \3 (message, silent) — see Con_MaskPrint in
// darkplaces/console.c. Using the same test means the sheet shows exactly what
// the feed showed, instead of a QC-side guess about what looks like chat.
float Touch_Chat_HistPitch(void)
{
	return TOUCH_FONT_READOUT_SM * Touch_UIScale() * 1.15 * 1.55;
}

void Touch_Chat_Capture(string msg)
{
	if (msg == "")
		return;
	float lead = str2chr(msg, 0);
	if (lead != 1 && lead != 3)
		return;

	string line = substring(msg, 1, strlen(msg) - 1);
	// Team chat carries a second marker byte before the text.
	if (strlen(line) > 0 && str2chr(line, 0) < 32)
		line = substring(line, 1, strlen(line) - 1);
	line = strreplace("\n", "", line);
	if (line == "")
		return;

	// Pinned to the bottom unless the reader has scrolled up: then the lines under
	// the finger stay put (the same rule as TouchChatLog_PinAdjust in the engine).
	if (touch_chat_hist_off > 0.5)
		touch_chat_hist_off += Touch_Chat_HistPitch();
	strcpy(touch_chat_line[touch_chat_head], line);
	touch_chat_head = (touch_chat_head + 1) % TOUCH_CHAT_HISTORY;
	if (touch_chat_count < TOUCH_CHAT_HISTORY)
		touch_chat_count += 1;
}

// ---------------------------------------------------------------------------
// @mentions
// ---------------------------------------------------------------------------

bool Touch_Chat_IsWordChar(string c)
{
	if (c == "" || c == "_")
		return c == "_";
	float k = str2chr(c, 0);
	return (k >= 48 && k <= 57) || (k >= 65 && k <= 90) || (k >= 97 && k <= 122) || k >= 128;
}

// Same rule as touch_mention_logic.h: "@name" in any case, not followed by more
// of a word, and the @ not glued to a word before it.
string Touch_Chat_Mark(string msg)
{
	if (msg == "" || str2chr(msg, 0) != 1 || !cvar("touch_chat_mentions"))
		return msg;
	string me = strtolower(strdecolorize(cvar_string("_cl_name")));
	if (me == "")
		return msg;
	string key = strcat("@", me);
	string low = strtolower(msg);
	int klen = strlen(key);
	string out = "";
	int from = 0, hit = 0;
	for (;;)
	{
		int pos = strstrofs(low, key, from);
		if (pos < 0)
			break;
		bool ok = (pos == 0 || !Touch_Chat_IsWordChar(substring(low, pos - 1, 1)))
			&& !Touch_Chat_IsWordChar(substring(low, pos + klen, 1));
		if (ok)
		{
			out = strcat(out, substring(msg, from, pos - from), "^xfc0", substring(msg, pos, klen), "^7");
			hit += 1;
		}
		else
			out = strcat(out, substring(msg, from, pos - from + klen));
		from = pos + klen;
	}
	if (!hit)
		return msg;
	localcmd("\nplay2 misc/talk2.wav\n");
	return strcat(out, substring(msg, from, strlen(msg) - from));
}

// The roster the engine's @ list and this sheet share: one line per player or
// spectator, "slot<TAB>p|s<TAB>name", names with their colour codes (the readers
// strip them for matching). Built from what the scoreboard already knows
// (playerslots / entcs), published to _touch_roster when it changes.
string touch_roster_last;

void Touch_Roster_Publish(void)
{
	string out = "";
	int i;
	for (i = 0; i < maxclients; i += 1)
	{
		if (!playerslots[i].gotscores || i == player_localentnum - 1)
			continue;
		string name = entcs_GetName(i);
		if (name == "")
			continue;
		string kind = "p";
		if (entcs_GetSpecState(i) == ENTCS_SPEC_PURE)
			kind = "s";
		out = strcat(out, ftos(i), "\t", kind, "\t", name, "\n");
	}
	if (out != touch_roster_last)
	{
		strcpy(touch_roster_last, out);
		cvar_set("_touch_roster", out);
	}
}

// The picker over the field: players and spectators from _touch_roster (the
// engine's copy of the scoreboard names, colour codes stripped).

int Touch_Chat_Token(string s)
{
	int n = strlen(s), i;
	for (i = n - 1; i >= 0; i -= 1)
	{
		if (substring(s, i, 1) == "@")
			return (i == 0 || substring(s, i - 1, 1) == " ") ? i : -1;
		if (n - i > 64)
			return -1;
	}
	return -1;
}

void Touch_Chat_PickRefresh(void)
{
	cvar_set("_touch_sheet_dbg", strcat("open=", ftos(touch_chat_open), " text=", touch_chat_text, " caret=", ftos(touch_chat_caret)));
	string key = strcat(ftos(touch_chat_caret), ":", touch_chat_text);
	if (key == touch_chat_pick_for)
		return;
	strcpy(touch_chat_pick_for, key);
	touch_chat_pick_n = 0;
	touch_chat_pick_hot = -1;
	touch_chat_pick_off = 0;
	if (!cvar("touch_chat_mentions"))
		return;
	string upto = substring(touch_chat_text, 0, touch_chat_caret);
	int at = Touch_Chat_Token(upto);
	if (at < 0)
		return;
	touch_chat_pick_at = at;
	string q = strtolower(substring(upto, at + 1, strlen(upto) - at - 1));
	int count = tokenizebyseparator(cvar_string("_touch_roster_all"), "\n");
	string names[64];
	bool spec[64];
	int i, pass;
	if (count > 64)
		count = 64;
	for (i = 0; i < count; i += 1)
	{
		string raw = argv(i);
		// "slot<TAB>p|s<TAB>name"
		int t1 = strstrofs(raw, "\t", 0);
		int t2 = (t1 < 0) ? -1 : strstrofs(raw, "\t", t1 + 1);
		spec[i] = false;
		if (t2 > 0 && substring(raw, t1 + 1, 1) == "s")
			spec[i] = true;
		names[i] = (t2 > 0) ? strdecolorize(substring(raw, t2 + 1, strlen(raw) - t2 - 1)) : "";
	}
	for (pass = 2; pass >= 1; pass -= 1)
		for (i = 0; i < count && touch_chat_pick_n < TOUCH_CHAT_PICK_MAX; i += 1)
		{
			if (names[i] == "")
				continue;
			int p = (q == "") ? 0 : strstrofs(strtolower(names[i]), q, 0);
			int score = (p == 0) ? 2 : ((p > 0) ? 1 : 0);
			if (score != pass)
				continue;
			strcpy(touch_chat_pick_name[touch_chat_pick_n], names[i]);
			touch_chat_pick_spec[touch_chat_pick_n] = spec[i];
			touch_chat_pick_n += 1;
		}
	cvar_set("_touch_sheet_pick", strcat(ftos(touch_chat_pick_n), ":", (touch_chat_pick_n ? touch_chat_pick_name[0] : "")));
}

void Touch_Chat_PickAccept(int row)
{
	if (row < 0 || row >= touch_chat_pick_n)
		return;
	string head = strcat(substring(touch_chat_text, 0, touch_chat_pick_at), "@",
		touch_chat_pick_name[row], " ");
	string tail = substring(touch_chat_text, touch_chat_caret, strlen(touch_chat_text) - touch_chat_caret);
	// exactly one space after the name: one already there is used, not doubled
	if (substring(tail, 0, 1) == " ")
		tail = substring(tail, 1, strlen(tail) - 1);
	if (strlen(head) + strlen(tail) <= autocvar_touch_kb_maxlen)
	{
		strcpy(touch_chat_text, strcat(head, tail));
		touch_chat_caret = strlen(head);
	}
	touch_chat_pick_n = 0;
}

// Space after "@fi": when "fi" is not already a player's exact name and something
// matches, the best match replaces it ("@fishman "), and the space is used up.
// Returns true when it did that; false means the space is typed as usual.
bool Touch_Chat_PickSpace(void)
{
	Touch_Chat_PickRefresh();
	if (touch_chat_pick_n <= 0)
		return false;
	string upto = substring(touch_chat_text, 0, touch_chat_caret);
	string q = strtolower(substring(upto, touch_chat_pick_at + 1, strlen(upto) - touch_chat_pick_at - 1));
	if (q == "")
		return false;
	int i;
	for (i = 0; i < touch_chat_pick_n; i += 1)
		if (strtolower(touch_chat_pick_name[i]) == q)
			return false;
	Touch_Chat_PickAccept(0);
	return true;
}

float Touch_Chat_PickRowH(void)
{
	return Touch_MMToUnits(TOUCH_MM_COMFORT) * 0.8;
}

// The list sits BELOW the field when it fits above the sheet's bottom edge (the
// chat wedge is at the top of the screen, and the field is just under the header
// so there is nearly always room); only when it does not, it goes above the field.
float Touch_Chat_PickBelowStart(void)
{
	return Touch_Chat_FieldCenter().y + Touch_Chat_FieldHalf().y + Touch_Chat_Pad() * 0.5;
}

bool Touch_Chat_PickBelow(void)
{
	int shown = min(touch_chat_pick_n, TOUCH_CHAT_PICK_ROWS);
	float h = Touch_Chat_PickRowH();
	float extra = (touch_chat_pick_n > TOUCH_CHAT_PICK_ROWS) ? h : 0;
	float limit = Touch_Chat_SheetCenter().y + Touch_Chat_InnerHalf().y;
	return Touch_Chat_PickBelowStart() + shown * h + extra <= limit;
}

vector Touch_Chat_PickRowCenter(int row)
{
	vector fc = Touch_Chat_FieldCenter();
	vector fh = Touch_Chat_FieldHalf();
	float h = Touch_Chat_PickRowH();
	if (Touch_Chat_PickBelow())
		return eX * fc.x + eY * (Touch_Chat_PickBelowStart() + (row + 0.5) * h);
	// above the typing line, which is above the field
	float top = fc.y - fh.y - h * 0.8;
	return eX * fc.x + eY * (top - (row + 0.5) * h);
}

vector Touch_Chat_PickRowHalf(void)
{
	return eX * Touch_Chat_FieldHalf().x + eY * (Touch_Chat_PickRowH() * 0.5);
}

int Touch_Chat_PickHit(vector p)
{
	int i;
	for (i = 0; i < TOUCH_CHAT_PICK_ROWS && touch_chat_pick_off + i < touch_chat_pick_n; i += 1)
		if (Touch_HitRectPx(p, Touch_Chat_PickRowCenter(i), Touch_Chat_PickRowHalf(), 1.0))
			return touch_chat_pick_off + i;
	return -1;
}

// The history area: under the field, down to the sheet's bottom edge.
float Touch_Chat_HistTop(void)
{
	return Touch_Chat_FieldCenter().y + Touch_Chat_FieldHalf().y + TOUCH_SPACE_2 * Touch_UIScale();
}

float Touch_Chat_HistBottom(void)
{
	return Touch_Chat_SheetCenter().y + Touch_Chat_InnerHalf().y;
}

bool Touch_Chat_HistHit(vector p)
{
	vector c = Touch_Chat_SheetCenter();
	vector inner = Touch_Chat_InnerHalf();
	return fabs(p.x - c.x) <= inner.x && p.y >= Touch_Chat_HistTop() && p.y <= Touch_Chat_HistBottom();
}

// The furthest the backlog can be pulled: the oldest line at the top.
float Touch_Chat_HistMax(void)
{
	float pitch = Touch_Chat_HistPitch();
	int fits = floor((Touch_Chat_HistBottom() - Touch_Chat_HistTop()) / pitch);
	return max(0, (touch_chat_count - fits) * pitch);
}

// 0 is the oldest line still held.
string Touch_Chat_Line(int i)
{
	if (i < 0 || i >= touch_chat_count)
		return "";
	int oldest = (touch_chat_head - touch_chat_count + TOUCH_CHAT_HISTORY) % TOUCH_CHAT_HISTORY;
	return touch_chat_line[(oldest + i) % TOUCH_CHAT_HISTORY];
}

// ---------------------------------------------------------------------------
// Pill
// ---------------------------------------------------------------------------

vector Touch_Chat_PillCenter(void)
{
	return Touch_WidgetCenter(autocvar_touch_chat_x, autocvar_touch_chat_y,
		autocvar_touch_chat_size);
}

vector Touch_Chat_PillHalf(void)
{
	if (cvar("_touch_topbar_active"))
		return eX * cvar("touch_chat_bar_w") * Touch_UISize().x * 0.5 + eY * cvar("touch_chat_bar_h") * Touch_UISize().y * 0.5;
	return Touch_WidgetHalfExtents(autocvar_touch_chat_size, autocvar_touch_chat_aspect);
}

bool Touch_Chat_PillHit(vector p)
{
	if (!autocvar_touch_chat_visible)
		return false;
	if (cvar("_touch_topbar_active"))
	{
		vector d = p - Touch_Chat_PillCenter();
		vector h = Touch_Chat_PillHalf();
		return fabs(d.x) <= h.x && fabs(d.y) <= h.y;
	}
	return Touch_HitRect(p, autocvar_touch_chat_x, autocvar_touch_chat_y,
		autocvar_touch_chat_size, autocvar_touch_chat_aspect, 1.20);
}

void Touch_Chat_DrawPill(float alpha)
{
	if (!autocvar_touch_chat_visible)
		return;
	Touch_Widget_ChromePill(Touch_Chat_PillCenter(), Touch_Chat_PillHalf(), "CHAT",
		touch_chat_pill_arming, alpha, TOUCH_C_ACCENT);
}

// ---------------------------------------------------------------------------
// The chat feed, its icons and the chat log (engine: touch_chatlog.c). The
// engine draws them and decides what a press means: it publishes the area that
// takes a finger, as fractions of the screen, in _touch_chatlog_claim
// ("x y w h"; the whole screen while the log is open). A finger that lands in
// it is ours from down to up, and is forwarded as touch_chatlog_ptr
// down|move|up <fx> <fy> (fractions too): taps on icons and names, dragging and
// flinging the log. A finger elsewhere is not ours.
// ---------------------------------------------------------------------------
bool touch_chatlog_active;     // a finger is in the claimed area

bool Touch_ChatLog_Hit(vector p)
{
	if (Touch_Chat_Active() || !cvar("touch_chatlog"))
		return false;
	if (tokenize_console(cvar_string("_touch_chatlog_claim")) < 4)
		return false;
	vector ui = Touch_UISize();
	float x = stof(argv(0)) * ui.x;
	float y = stof(argv(1)) * ui.y;
	float w = stof(argv(2)) * ui.x;
	float h = stof(argv(3)) * ui.y;
	return p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h;
}

void Touch_ChatLog_Forward(string phase, vector p)
{
	vector ui = Touch_UISize();
	if (ui.x <= 0 || ui.y <= 0)
		return;
	localcmd(sprintf("\ntouch_chatlog_ptr %s %f %f\n", phase, p.x / ui.x, p.y / ui.y));
}

int Touch_Chat_OnDown(vector p)
{
	if (Touch_ChatLog_Hit(p))
	{
		touch_chatlog_active = true;
		Touch_ChatLog_Forward("down", p);
		return TOUCH_ROLE_CHAT;
	}
	if (!Touch_Chat_PillHit(p))
		return TOUCH_ROLE_NONE;
	touch_chat_pill_arming = true;
	touch_chat_pill_down = p;
	return TOUCH_ROLE_CHAT;
}

void Touch_Chat_OnMove(vector p)
{
	if (touch_chatlog_active)
	{
		Touch_ChatLog_Forward("move", p);
		return;
	}
	if (!touch_chat_pill_arming)
		return;
	vector d = p - touch_chat_pill_down;
	d.z = 0;
	// Same slop rule as the other pills: a look swipe that begins on the pill is
	// a swipe, not a press.
	if (vlen(d) > autocvar_touch_pause_slop_px)
		touch_chat_pill_arming = false;
}

void Touch_Chat_OnUp(vector p)
{
	if (touch_chatlog_active)
	{
		touch_chatlog_active = false;
		Touch_ChatLog_Forward("up", p);
		return;
	}
	if (touch_chat_pill_arming)
	{
		vector d = p - touch_chat_pill_down;
		d.z = 0;
		if (vlen(d) <= autocvar_touch_pause_slop_px)
			Touch_Chat_Open(false);
	}
	touch_chat_pill_arming = false;
}

bool Touch_Chat_Busy(void)
{
	return touch_chat_pill_arming;
}

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------

bool Touch_Chat_Active(void)
{
	return cvar("vid_touchscreen") && touch_chat_open;
}

void Touch_Chat_Open(bool team)
{
	// Everything held must be let go: the sheet covers the controls, so a key
	// still down would be stuck down for as long as the sheet is open.
	Touch_ReleaseAll();
	Touch_Kb_Reset();
	Touch_Pointer_Clear();
	// The transient feed is drawn by the *engine*, after CSQC, so it lands on top
	// of the sheet no matter how opaque the sheet is — the composer opened with
	// "no messages yet" in the middle of it and live chat lines printed across it.
	// Setting the panel off makes HUD_Chat park con_chat/con_chatrect, and turning
	// it back on restores them. The sheet's own backlog is the feed while it is up.
	cvar_set("hud_panel_chat", "0");
	cvar_set("_touch_chat_sheet", "1"); // the engine's console button keeps off the sheet's header
	touch_chat_open = true;
	touch_chat_team = team;
	touch_chat_hot_row = -1;
	touch_chat_hot_cell = -1;
	touch_chat_hot_button = TOUCH_CHAT_BTN_NONE;
	strcpy(touch_chat_text, "");
	touch_chat_caret = 0;
}

void Touch_Chat_Close(void)
{
	touch_chat_open = false;
	touch_chat_pill_arming = false;
	cvar_set("hud_panel_chat", "1");
	cvar_set("_touch_chat_sheet", "0");
	Touch_Pointer_Clear();
	strcpy(touch_chat_text, "");
	touch_chat_caret = 0;
}

void Touch_Chat_Send(void);

// ---------------------------------------------------------------------------
// Local echo: our own message shows the moment it is sent, and the server's echo
// of it is dropped when it arrives, so the line is there once. Only plain `say`:
// the server formats team messages and tells (prefix, team colour) in ways a
// client would only be guessing at. If the server never echoes (muted, or the
// message was filtered) the local line stays; there is nothing to retract it with.
// ---------------------------------------------------------------------------
const int TOUCH_CHAT_ECHO_MAX = 4;
string touch_echo_text[TOUCH_CHAT_ECHO_MAX];
float touch_echo_time[TOUCH_CHAT_ECHO_MAX];
int touch_echo_n;

void Touch_Chat_LocalEcho(string text)
{
	string line = strcat("\1", cvar_string("_cl_name"), "^7: ", text, "\n");
	Touch_Chat_Capture(line);
	print(ColorTranslateRGB(line));
	if (touch_echo_n >= TOUCH_CHAT_ECHO_MAX)
	{
		int i;
		for (i = 1; i < TOUCH_CHAT_ECHO_MAX; i += 1)
		{
			strcpy(touch_echo_text[i - 1], touch_echo_text[i]);
			touch_echo_time[i - 1] = touch_echo_time[i];
		}
		touch_echo_n -= 1;
	}
	strcpy(touch_echo_text[touch_echo_n], text);
	touch_echo_time[touch_echo_n] = time;
	touch_echo_n += 1;
}

// A chat line from the server: true when it is the echo of what we just said.
bool Touch_Chat_IsEcho(string msg)
{
	if (touch_echo_n <= 0 || str2chr(msg, 0) != 1)
		return false;
	string plain = strdecolorize(msg);
	string me = strdecolorize(cvar_string("_cl_name"));
	int i;
	for (i = 0; i < touch_echo_n; i += 1)
	{
		if (time - touch_echo_time[i] > 10)
			continue;
		string want = strcat(me, ": ", touch_echo_text[i]);
		int at = strstrofs(plain, want, 0);
		if (at < 0)
			continue;
		// remove it from the list
		int j;
		for (j = i + 1; j < touch_echo_n; j += 1)
		{
			strcpy(touch_echo_text[j - 1], touch_echo_text[j]);
			touch_echo_time[j - 1] = touch_echo_time[j];
		}
		touch_echo_n -= 1;
		return true;
	}
	return false;
}

bool Touch_Chat_KeyEvent(float bInputType, float nPrimary, float nSecondary)
{
	if (!Touch_Chat_Active() || (bInputType != 0 && bInputType != 1))
		return false;
	// Mouse buttons and the wheel are the pointer's, handled with the sheet's
	// other presses.
	if (nPrimary >= K_MOUSE1 && nPrimary <= K_MOUSE16)
		return false;
	if (nPrimary == K_MWHEELUP || nPrimary == K_MWHEELDOWN)
		return false;
	if (bInputType == 1)
		return true;
	Touch_Chat_PickRefresh();
	// Moving the caret: the arrows, Home, End; Delete removes the character after it.
	int len = strlen(touch_chat_text);
	if (nPrimary == K_LEFTARROW || nPrimary == K_RIGHTARROW || nPrimary == K_HOME || nPrimary == K_END)
	{
		if (nPrimary == K_LEFTARROW)
			touch_chat_caret = max(0, touch_chat_caret - 1);
		else if (nPrimary == K_RIGHTARROW)
			touch_chat_caret = min(len, touch_chat_caret + 1);
		else
			touch_chat_caret = (nPrimary == K_HOME) ? 0 : len;
		Touch_Widget_FieldTouched();
		return true;
	}
	if (nPrimary == K_DEL)
	{
		if (touch_chat_caret < len)
		{
			strcpy(touch_chat_text, strcat(substring(touch_chat_text, 0, touch_chat_caret),
				substring(touch_chat_text, touch_chat_caret + 1, len - touch_chat_caret - 1)));
			Touch_Widget_FieldTouched();
		}
		return true;
	}
	if ((nPrimary == K_ENTER || nPrimary == K_KP_ENTER || nPrimary == K_TAB) && touch_chat_pick_n > 0)
		Touch_Chat_PickAccept(0);
	else if (nPrimary == K_ENTER || nPrimary == K_KP_ENTER)
		Touch_Chat_Send();
	else
	{
		// strcpy frees the old text before it reads the new one.
		// Typing and Backspace act on the text left of the caret; what is right of it stays.
		string left = substring(touch_chat_text, 0, touch_chat_caret);
		string right = substring(touch_chat_text, touch_chat_caret, strlen(touch_chat_text) - touch_chat_caret);
		string next = Touch_Kb_Type(left, nPrimary, nSecondary);
		if (next == strcat(left, " ") && Touch_Chat_PickSpace())
			return true;
		if (next != left)
		{
			strcpy(touch_chat_text, strcat(next, right));
			touch_chat_caret = strlen(next);
			Touch_Widget_FieldTouched();
		}
	}
	return true;
}

// Space is a full-width key next to SEND, so a run of stray spaces is an easy
// mistake. Sending it would put an empty line in everyone's feed.
bool Touch_Chat_IsBlank(string s)
{
	int i;
	for (i = 0; i < strlen(s); i += 1)
		if (substring(s, i, 1) != " ")
			return false;
	return true;
}

void Touch_Chat_Send(void)
{
	if (Touch_Chat_IsBlank(touch_chat_text))
	{
		Touch_Chat_Close();
		return;
	}
	// This string reaches a console command line, so it is escaped here at the
	// boundary rather than trusted because the on-screen keyboard "can only
	// produce safe characters". A quote or a newline would otherwise end the
	// argument and let the rest run as commands.
	string safe = MakeConsoleSafe(touch_chat_text);
	if (!touch_chat_team)
		Touch_Chat_LocalEcho(touch_chat_text);
	localcmd(strcat((touch_chat_team ? "say_team \"" : "say \""), safe, "\"\n"));
	Touch_Chat_Close();
}

// The sheet spans from the top margin down to just above the keyboard. Its
// geometry is shared by the surface, the header and the backlog so that the three
// cannot disagree about where the panel's edges are.
float Touch_Chat_SheetMargin(void)
{
	return TOUCH_SPACE_3 * Touch_UIScale();
}

vector Touch_Chat_SheetHalf(void)
{
	vector ui = Touch_UISize();
	float m = Touch_Chat_SheetMargin();
	float bottom = Touch_Kb_Top() - m * 0.5;
	// Same side margin as the keyboard below it, so the sheet's edge and the outer
	// key column line up down the screen instead of missing each other by 10 units.
	return eX * (ui.x * 0.5 - m) + eY * (max(4, bottom - m) * 0.5);
}

vector Touch_Chat_SheetCenter(void)
{
	vector ui = Touch_UISize();
	return eX * (ui.x * 0.5) + eY * (Touch_Chat_SheetMargin() + Touch_Chat_SheetHalf().y);
}

// Everything in the sheet is laid out against this inner box, not the screen, so
// nothing sits on the sheet's own edge.
float Touch_Chat_Pad(void)
{
	return TOUCH_SPACE_3 * Touch_UIScale();
}

vector Touch_Chat_InnerHalf(void)
{
	return Touch_Chat_SheetHalf() - '1 1 0' * Touch_Chat_Pad();
}

vector Touch_Chat_FieldHalf(void)
{
	return eX * Touch_Chat_InnerHalf().x
		+ eY * (Touch_MMToUnits(TOUCH_MM_COMFORT) * 0.7);
}

vector Touch_Chat_ButtonHalf(void);

// The input belongs immediately below the header, away from the keyboard.
vector Touch_Chat_FieldCenter(void)
{
	vector c = Touch_Chat_SheetCenter();
	vector half = Touch_Chat_FieldHalf();
	return eX * c.x + eY * (c.y - Touch_Chat_InnerHalf().y + Touch_Chat_ButtonHalf().y * 2 + Touch_Chat_Pad() + half.y);
}

vector Touch_Chat_ButtonHalf(void)
{
	float h = Touch_MMToUnits(TOUCH_MM_COMFORT) * 0.6;
	// As wide as they comfortably go, but never over the title on the left.
	float fs = TOUCH_FONT_READOUT * Touch_UIScale();
	float title = stringwidth("TEAM MESSAGE", false, '1 1 0' * fs);
	float gap = TOUCH_SPACE_2 * Touch_UIScale();
	float room = Touch_Chat_InnerHalf().x * 2 - title - gap * TOUCH_CHAT_BTN_COUNT;
	float w = min(h * 2.4, room / TOUCH_CHAT_BTN_COUNT * 0.5);
	return eX * max(h, w) + eY * h;
}

vector Touch_Chat_ButtonCenter(int idx)
{
	vector c = Touch_Chat_SheetCenter();
	vector inner = Touch_Chat_InnerHalf();
	vector half = Touch_Chat_ButtonHalf();
	float gap = TOUCH_SPACE_2 * Touch_UIScale();
	// Right-aligned header buttons, CLOSE outermost: the exit belongs at the edge
	// where it is hard to hit by accident mid-typing.
	float right = c.x + inner.x - half.x;
	float x = right - idx * (half.x * 2 + gap);
	return eX * x + eY * (c.y - inner.y + half.y);
}

int Touch_Chat_HitButton(vector p)
{
	int i;
	for (i = 0; i < TOUCH_CHAT_BTN_COUNT; i += 1)
		if (Touch_HitRectPx(p, Touch_Chat_ButtonCenter(i), Touch_Chat_ButtonHalf(), 1.15))
			return i;
	return TOUCH_CHAT_BTN_NONE;
}

void Touch_Chat_PointerDown(vector p)
{
	touch_chat_hot_row = -1;
	touch_chat_hot_cell = -1;
	touch_chat_hot_button = Touch_Chat_HitButton(p);
	if (touch_chat_hot_button != TOUCH_CHAT_BTN_NONE)
		return;
	Touch_Chat_PickRefresh();
	touch_chat_pick_hot = Touch_Chat_PickHit(p);
	if (touch_chat_pick_hot >= 0)
	{
		touch_chat_pick_press = true;
		touch_chat_pick_dragged = false;
		touch_chat_pick_y0 = p.y;
		touch_chat_pick_last_y = p.y;
		touch_chat_pick_last_t = time;
		touch_chat_pick_vel = 0;
		return;
	}
	// A finger in the text field places the caret, and dragging along it moves it.
	if (Touch_HitRectPx(p, Touch_Chat_FieldCenter(), Touch_Chat_FieldHalf(), 1.0))
	{
		touch_chat_field_hot = true;
		touch_chat_caret = Touch_Widget_FieldHit(p.x);
		Touch_Widget_FieldTouched();
		return;
	}
	if (Touch_Chat_HistHit(p) && touch_chat_count > 0)
	{
		touch_chat_hist_press = true;
		touch_chat_hist_vel = 0;
		touch_chat_hist_last_y = p.y;
		touch_chat_hist_last_t = time;
		return;
	}
	if (Touch_Kb_Hit(p))
	{
		touch_chat_hot_row = Touch_Kb_HitRow();
		touch_chat_hot_cell = Touch_Kb_HitCell();
		touch_chat_hot_time = time;
	}
}

void Touch_Chat_PointerMove(vector p)
{
	if (touch_chat_hist_press)
	{
		// The backlog follows the finger by the pixel; the speed is kept for the coast.
		float dy = p.y - touch_chat_hist_last_y;
		float dtm = time - touch_chat_hist_last_t;
		touch_chat_hist_off = bound(0, touch_chat_hist_off + dy, Touch_Chat_HistMax());
		if (dtm > 0)
			touch_chat_hist_vel = touch_chat_hist_vel * 0.6 + (dy / dtm) * 0.4;
		touch_chat_hist_last_y = p.y;
		touch_chat_hist_last_t = time;
		return;
	}
	if (touch_chat_pick_press)
	{
		// Dragging the list: it follows the finger, a row at a time.
		float rowh = Touch_Chat_PickRowH();
		float dy = p.y - touch_chat_pick_y0;
		if (fabs(dy) > rowh * 0.5)
			touch_chat_pick_dragged = true;
		// the flick's speed, in rows per second, for the coast after release
		if (time > touch_chat_pick_last_t)
		{
			float v = -(p.y - touch_chat_pick_last_y) / rowh / (time - touch_chat_pick_last_t);
			touch_chat_pick_vel = touch_chat_pick_vel * 0.6 + v * 0.4;
		}
		touch_chat_pick_last_y = p.y;
		touch_chat_pick_last_t = time;
		int rows = floor(fabs(dy) / rowh);
		if (rows > 0)
		{
			int dir = (dy > 0) ? -1 : 1;
			touch_chat_pick_off = bound(0, touch_chat_pick_off + dir * rows,
				max(0, touch_chat_pick_n - TOUCH_CHAT_PICK_ROWS));
			touch_chat_pick_y0 += ((dy > 0) ? 1 : -1) * rows * rowh;
		}
		return;
	}
	if (touch_chat_field_hot)
	{
		touch_chat_caret = Touch_Widget_FieldHit(p.x);
		Touch_Widget_FieldTouched();
		return;
	}
	if (touch_chat_hot_button != TOUCH_CHAT_BTN_NONE)
	{
		if (Touch_Chat_HitButton(p) != touch_chat_hot_button)
			touch_chat_hot_button = TOUCH_CHAT_BTN_NONE;
		return;
	}
	if (Touch_Kb_PopupOpen())
	{
		Touch_Kb_PopupSlide(p);
		return;
	}
	if (touch_chat_hot_row < 0)
		return;
	// Sliding off a key cancels it. On a key this small a slide is much more
	// likely to be a correction than a decision.
	Touch_Kb_Hit(p);
	if (Touch_Kb_HitRow() != touch_chat_hot_row || Touch_Kb_HitCell() != touch_chat_hot_cell)
	{
		touch_chat_hot_row = -1;
		touch_chat_hot_cell = -1;
	}
}

void Touch_Chat_PointerUp(void)
{
	if (touch_chat_hist_press)
	{
		touch_chat_hist_press = false;
		// stopped before letting go: no coast
		if (time - touch_chat_hist_last_t > 0.08)
			touch_chat_hist_vel = 0;
		return;
	}
	if (touch_chat_field_hot)
	{
		touch_chat_field_hot = false;
		return;
	}
	if (touch_chat_pick_press)
	{
		int row = touch_chat_pick_hot;
		touch_chat_pick_press = false;
		touch_chat_pick_hot = -1;
		if (!touch_chat_pick_dragged)
			Touch_Chat_PickAccept(row);
		return;
	}
	if (touch_chat_hot_button == TOUCH_CHAT_BTN_CLOSE)
	{
		Touch_Chat_Close();
		return;
	}
	if (Touch_Kb_PopupOpen())
	{
		touch_chat_hot_row = -1;
		touch_chat_hot_cell = -1;
		string c = Touch_Kb_PopupPick();
		if (c != "" && strlen(touch_chat_text) < autocvar_touch_kb_maxlen)
		{
			string picked = strcat(substring(touch_chat_text, 0, touch_chat_caret), c);
			string rest = substring(touch_chat_text, touch_chat_caret, strlen(touch_chat_text) - touch_chat_caret);
			strcpy(touch_chat_text, strcat(picked, rest));
			touch_chat_caret = strlen(picked);
			Touch_Widget_FieldTouched();
		}
		Touch_Kb_ReleaseShift();
		return;
	}
	if (touch_chat_hot_row < 0)
		return;

	int row = touch_chat_hot_row;
	int cell = touch_chat_hot_cell;
	touch_chat_hot_row = -1;
	touch_chat_hot_cell = -1;

	if (Touch_Kb_CellAction(row, cell) == TOUCH_KB_SEND)
	{
		Touch_Chat_Send();
		return;
	}
	// The new text has to be built *before* strcpy runs. strcpy(x, f(x)) is a
	// use-after-free: the macro strunzones its target first and only then
	// evaluates the argument, so f() reads a freed string. Every keypress read
	// the buffer as empty and the field held only the last character typed.
	string left = substring(touch_chat_text, 0, touch_chat_caret);
	string right = substring(touch_chat_text, touch_chat_caret, strlen(touch_chat_text) - touch_chat_caret);
	string next = Touch_Kb_Apply(left, row, cell);
	if (next == strcat(left, " ") && Touch_Chat_PickSpace())
		return;
	// Shift and ?123 hand back the text itself; strcpy would free it before
	// copying it, and the message was gone after every shift.
	if (next != left)
	{
		strcpy(touch_chat_text, strcat(next, right));
		touch_chat_caret = strlen(next);
		Touch_Widget_FieldTouched();
	}
}

void Touch_Chat_Frame(void)
{
	if (!Touch_Chat_Active())
		return;
	// A flicked @ list keeps scrolling a moment and slows to a stop.
	float dt = min(0.1, time - touch_chat_pick_tick);
	touch_chat_pick_tick = time;
	if (!touch_chat_pick_press && fabs(touch_chat_pick_vel) > 0.6 && touch_chat_pick_n > TOUCH_CHAT_PICK_ROWS)
	{
		touch_chat_pick_acc += touch_chat_pick_vel * dt;
		int whole = (touch_chat_pick_acc > 0) ? floor(touch_chat_pick_acc) : -floor(-touch_chat_pick_acc);
		if (whole != 0)
		{
			touch_chat_pick_off = bound(0, touch_chat_pick_off + whole, max(0, touch_chat_pick_n - TOUCH_CHAT_PICK_ROWS));
			touch_chat_pick_acc -= whole;
		}
		touch_chat_pick_vel *= pow(0.04, dt);
	}
	else if (!touch_chat_pick_press)
		touch_chat_pick_vel = 0;
	// The backlog keeps coasting after a flick, slowing to a stop, and halts at either end.
	if (!touch_chat_hist_press && touch_chat_hist_vel != 0)
	{
		float hmax = Touch_Chat_HistMax();
		touch_chat_hist_off += touch_chat_hist_vel * dt;
		touch_chat_hist_vel *= exp(-3.5 * dt);
		if (fabs(touch_chat_hist_vel) < 4 || touch_chat_hist_off <= 0 || touch_chat_hist_off >= hmax)
			touch_chat_hist_vel = 0;
		touch_chat_hist_off = bound(0, touch_chat_hist_off, hmax);
	}
	// Keys are released on open, but a sheet that stays open across a respawn
	// must not let anything creep back on.
	Touch_ReleaseAll();

	Touch_Pointer_Frame();
	if (Touch_Pointer_Pressed())
		Touch_Chat_PointerDown(Touch_Pointer_Pos());
	else if (Touch_Pointer_Released())
		Touch_Chat_PointerUp();
	else if (Touch_Pointer_IsDown())
	{
		Touch_Chat_PointerMove(Touch_Pointer_Pos());
		// Held on a character with variants: they pop up over the key. Keys
		// type on release, so the timer never holds back a tap.
		if (touch_chat_hot_row >= 0)
			Touch_Kb_HoldCheck(touch_chat_hot_row, touch_chat_hot_cell, time - touch_chat_hot_time);
	}
}

void Touch_Chat_DrawHistory(float alpha)
{
	vector c = Touch_Chat_SheetCenter();
	vector inner = Touch_Chat_InnerHalf();
	float left = c.x - inner.x;
	// Between the header row and the field, both of which are already placed
	// against the same inner box.
	float top = Touch_Chat_FieldCenter().y + Touch_Chat_FieldHalf().y
		+ TOUCH_SPACE_2 * Touch_UIScale();
	float bottom = c.y + inner.y;

	float fs = TOUCH_FONT_READOUT_SM * Touch_UIScale() * 1.15;
	float pitch = fs * 1.55;
	int fits = floor((bottom - top) / pitch);
	if (fits < 1)
		return;

	if (touch_chat_count <= 0)
	{
		Touch_Shape_Label(eX * c.x + eY * ((top + bottom) * 0.5), fs,
			"no messages yet", TOUCH_C_RIM, alpha * TOUCH_A_GHOST * 3);
		return;
	}

	// Newest at the bottom, next to the field being typed in, so the reply is
	// beside what it replies to. Pulled down by hist_off pixels; only the rows
	// that touch the area are looked up and drawn, however long the backlog is.
	touch_chat_hist_off = bound(0, touch_chat_hist_off, max(0, (touch_chat_count - fits) * pitch));
	float area_top = bottom - fits * pitch;
	int whole = floor(touch_chat_hist_off / pitch);
	float frac = touch_chat_hist_off - whole * pitch;
	int j0 = touch_chat_count - fits - whole;
	int mfirst = (frac > 0.001) ? -1 : 0;
	int mlast = fits - 1;
	if (j0 + mfirst < 0)
		mfirst = -j0;
	if (j0 + mlast > touch_chat_count - 1)
		mlast = touch_chat_count - 1 - j0;
	drawsetcliparea_builtin(left, area_top, inner.x * 2, fits * pitch);
	int m;
	for (m = mfirst; m <= mlast; m += 1)
	{
		string line = Touch_Chat_Line(j0 + m);
		float y = area_top + m * pitch + frac;
		// Colour-coded: player names carry team and identity colours, and
		// stripping them would lose who said what.
		drawcolorcodedstring(eX * left + eY * (y + (pitch - fs) * 0.5), line, '1 1 0' * fs,
			alpha * TOUCH_A_INK, DRAWFLAG_NORMAL);
		Touch_DebugAddFills(1);
	}
	drawresetcliparea();
}

void Touch_Chat_Draw(void)
{
	if (!Touch_Chat_Active())
		return;

	vector ui = Touch_UISize();
	float alpha = 1.0;

	// Modal: the scrim says the game is not listening to the controls.
	drawfill_builtin('0 0 0', ui, TOUCH_C_SURFACE, TOUCH_A_SCRIM, DRAWFLAG_NORMAL);
	Touch_DebugAddFills(1);

	// A dim alone is not enough. A scrim leaves whatever is behind it legible, and
	// while the player is dead the stock scoreboard is a screenful of white text
	// that read straight through the backlog. So the sheet is an actual surface
	// with an edge (Law of Common Region), the way a GNOME dialog is, rather than
	// text floating on a darkened game.
	float sheet_r = TOUCH_R_MD * Touch_UIScale();
	Touch_Shape_RRect(Touch_Chat_SheetCenter(), Touch_Chat_SheetHalf(), sheet_r,
		TOUCH_C_SURFACE, TOUCH_A_SHEET);
	Touch_Shape_RRectRing(Touch_Chat_SheetCenter(), Touch_Chat_SheetHalf(), sheet_r,
		TOUCH_W_STROKE * Touch_UIScale(), TOUCH_C_RIM, alpha * TOUCH_A_GHOST * 2);
	vector bhalf = Touch_Chat_ButtonHalf();
	vector sc = Touch_Chat_SheetCenter();
	vector inner = Touch_Chat_InnerHalf();
	Touch_Shape_LabelAligned(eX * (sc.x - inner.x) + eY * (sc.y - inner.y + bhalf.y),
		TOUCH_FONT_READOUT * Touch_UIScale(),
		(touch_chat_team ? "TEAM MESSAGE" : "MESSAGE"), -1, TOUCH_C_INK,
		alpha * TOUCH_A_INK);

	Touch_Widget_Key(Touch_Chat_ButtonCenter(TOUCH_CHAT_BTN_CLOSE), bhalf, "CLOSE",
		touch_chat_hot_button == TOUCH_CHAT_BTN_CLOSE, false, false, alpha,
		TOUCH_C_DANGER);
	Touch_Chat_DrawHistory(alpha);
	Touch_Chat_PickRefresh();
	// Who is typing, from the engine (the server's chat bubbles), over the field.
	string typing = cvar_string("_touch_typing");
	if (typing != "")
		Touch_Shape_LabelAligned(eX * (sc.x - inner.x) + eY * (Touch_Chat_FieldCenter().y - Touch_Chat_FieldHalf().y - Touch_Chat_PickRowH() * 0.4),
			TOUCH_FONT_READOUT_SM * Touch_UIScale(), typing, -1, TOUCH_C_INK, alpha * TOUCH_A_INK);
	int pi;
	int pshown = min(touch_chat_pick_n - touch_chat_pick_off, TOUCH_CHAT_PICK_ROWS);
	if (pshown > 0)
	{
		// Tinted glass like the other panels: translucent dark body, light rim, rounded corners.
		float prow = Touch_Chat_PickRowH();
		vector pc = (Touch_Chat_PickRowCenter(0) + Touch_Chat_PickRowCenter(pshown - 1)) * 0.5;
		vector ph = Touch_Chat_PickRowHalf() + eY * (prow * (pshown - 1) * 0.5);
		float pr = TOUCH_R_MD * Touch_UIScale();
		Touch_Shape_RRect(pc, ph, pr, TOUCH_GLASS_SHADOW, alpha * 0.66);
		Touch_Shape_RRectRing(pc, ph, pr, TOUCH_W_STROKE * Touch_UIScale(), TOUCH_GLASS_HIGHLIGHT, alpha * 0.30);
		for (pi = 0; pi < pshown; pi += 1)
		{
			int at = touch_chat_pick_off + pi;
			vector rc = Touch_Chat_PickRowCenter(pi);
			vector rh = Touch_Chat_PickRowHalf();
			if (touch_chat_pick_hot == at)
				Touch_Shape_RRect(rc, rh - '3 3 0' * Touch_UIScale(), TOUCH_R_SM * Touch_UIScale(), TOUCH_GLASS_ACCENT, alpha * 0.45);
			string lab = strcat("@", touch_chat_pick_name[at], (touch_chat_pick_spec[at] ? "   spectator" : ""));
			Touch_Shape_LabelAligned(eX * (rc.x - rh.x + Touch_Chat_Pad()) + eY * rc.y,
				Touch_Widget_LabelSize(rh, lab), lab, -1, TOUCH_C_INK, alpha * TOUCH_A_INK);
		}
	}
	// More names than rows: a count says so, and a drag over the list scrolls it.
	if (touch_chat_pick_n > TOUCH_CHAT_PICK_ROWS && pshown > 0)
	{
		float cdir = Touch_Chat_PickBelow() ? 1 : -1;
		Touch_Shape_LabelAligned(Touch_Chat_PickRowCenter(pshown - 1) + eX * (Touch_Chat_PickRowHalf().x - TOUCH_SPACE_3 * Touch_UIScale()) + eY * cdir * Touch_Chat_PickRowH(),
			TOUCH_FONT_READOUT_SM * Touch_UIScale(),
			strcat(ftos(touch_chat_pick_off + 1), "-", ftos(min(touch_chat_pick_n, touch_chat_pick_off + TOUCH_CHAT_PICK_ROWS)), " of ", ftos(touch_chat_pick_n)),
			1, TOUCH_C_INK, alpha * TOUCH_A_INK);
	}

	Touch_Widget_Field(Touch_Chat_FieldCenter(), Touch_Chat_FieldHalf(),
		touch_chat_text, "tap to type…", alpha, TOUCH_C_ACCENT, touch_chat_caret);

	Touch_Kb_Draw(alpha, touch_chat_hot_row, touch_chat_hot_cell);
}
