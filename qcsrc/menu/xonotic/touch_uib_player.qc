// SPDX-License-Identifier: GPL-3.0-or-later
// Godnotic UI bridge: Settings > Player on one page (docs/SETTINGS_MAP.md, "Player").
//
//   Name        the field, then one swatch per colour code ^0..^9 (a tap writes the code
//               at the end of the name)
//   Character   the model's picture with arrows to flip through every model: the game's
//               stock ones and the player's own uploads, in one cycle; its name under it
//   Colours     shirt and pants (_cl_color), the colours the character wears in a match
//   Upload      the system file picker; a model that passes the engine's check
//               (touch_playermodel.c) becomes the character at once, one that does not
//               says why and changes nothing
//
// The picture is the model's own preview image (models/player/<name>.<fmt>_<skin>.jpg), which the
// engine resizes and caches like any bridge image: no 3D view, so nothing loads and
// nothing is drawn per frame, on Android and on Linux alike. An uploaded model has none
// and shows the placeholder; the shirt and pants colours are shown beside the picture.
// Uploaded models live in <userdir>/godnotic-pm-*.pk3 and are deleted only by the model's
// own delete button.

const int UIB_PM_MAX = 96;
string uib_pm_model[UIB_PM_MAX];
string uib_pm_skin[UIB_PM_MAX];
string uib_pm_title[UIB_PM_MAX];
bool uib_pm_up[UIB_PM_MAX];
int uib_pm_n = -1;   // -1: not read yet (after an upload or a delete: read again)

string UIB_PMNameHex(int i)
{
	switch (i)
	{
		case 0: return "#000000"; case 1: return "#ff0000"; case 2: return "#00ff00"; case 3: return "#ffff00";
		case 4: return "#0000ff"; case 5: return "#00ffff"; case 6: return "#ff00ff"; case 7: return "#ffffff";
		case 8: return "#999999"; case 9: return "#808080";
	}
	return "#ffffff";
}

void UIB_PMLoad()
{
	if (uib_pm_n >= 0) return;
	for (int i = 0; i < UIB_PM_MAX; ++i)
		if (uib_pm_model[i] != "")
		{
			strunzone(uib_pm_model[i]); strunzone(uib_pm_skin[i]); strunzone(uib_pm_title[i]);
			uib_pm_model[i] = ""; uib_pm_skin[i] = ""; uib_pm_title[i] = "";
		}
	uib_pm_n = 0;
	// the models the player uploaded, one "\n<name>\n" each
	string reg = "";
	if (cvar_string("uib_pm") != "")
	{
		int fh = fopen("godnotic-playermodels.txt", FILE_READ);
		if (fh >= 0)
		{
			string l;
			while ((l = fgets(fh)))
				if (tokenizebyseparator(l, "\t") >= 3)
					reg = strcat(reg, "\n", argv(1), "\n");
			fclose(fh);
		}
	}
	float glob = search_begin(get_model_datafilename(string_null, -1, "txt"), true, true);
	if (glob < 0) return;
	float sortbuf = buf_create();
	for (int i = 0; i < search_getsize(glob); ++i)
	{
		string fn = search_getfilename(glob, i);
		if (!get_model_parameters(fn, -1)) continue;
		if (get_model_parameters_hidden) continue;
		bufstr_add(sortbuf, sprintf("%-128s%s", get_model_parameters_name, fn), 1);
	}
	search_end(glob);
	buf_sort(sortbuf, 128, 0);
	int n = buf_getsize(sortbuf);
	for (int i = 0; i < n && uib_pm_n < UIB_PM_MAX; ++i)
	{
		string fn = substring(bufstr_get(sortbuf, i), 128, -1);
		if (!get_model_parameters(fn, -1)) continue;
		int k = uib_pm_n++;
		uib_pm_model[k] = strzone(get_model_parameters_modelname);
		uib_pm_skin[k] = strzone(ftos(get_model_parameters_modelskin));
		uib_pm_title[k] = strzone(get_model_parameters_name);
		uib_pm_up[k] = strstrofs(reg, strcat("\n", get_model_parameters_modelname, "\n"), 0) >= 0;
	}
	buf_del(sortbuf);
	get_model_parameters(string_null, 0);
}

// the list position of the model in _cl_playermodel/_cl_playerskin, or -1
int UIB_PMCurrent()
{
	string m = cvar_string("_cl_playermodel"), s = cvar_string("_cl_playerskin");
	for (int i = 0; i < uib_pm_n; ++i)
		if (uib_pm_model[i] == m && uib_pm_skin[i] == s)
			return i;
	return -1;
}

void UIB_PMSelect(int i)
{
	cvar_set("_cl_playermodel", uib_pm_model[i]);
	cvar_set("_cl_playerskin", uib_pm_skin[i]);
	localcmd("\nplayermodel $_cl_playermodel; playerskin $_cl_playerskin\nsaveconfig\n");
}

void UIB_PlayerPage()
{
	UIB_PMLoad();
	int cur = UIB_PMCurrent();
	string nm = cvar_string("_cl_name");

	UIB_Section("who", _("Name"), true);
	UIB_Open("name", "field");
		uib_s("label", _("Name"));
		uib_s("bind", "vm:player.name");
		uib_s("value", strreplace("^", "^^", nm));   // the field shows and edits the codes themselves
		uib_s("kind", "name");
		uib_f("maxLength", 32);
		UIB_Apply("reconnect");
	UIB_Close();
	UIB_Open("namecolours", "colour");
		uib_s("label", _("Name colours"));
		uib_s("help", _("Tap a colour to add its code (^0 to ^9) to the end of the name"));
		uib_s("bind", "vm:player.namecolour");
		string pal = "[", labels = "[";
		for (int i = 0; i < 10; ++i)
		{
			pal = strcat(pal, (i ? "," : ""), "\"", UIB_PMNameHex(i), "\"");
			labels = strcat(labels, (i ? "," : ""), "\"", ftos(i), "\"");
		}
		uib_j("palette", strcat(pal, "]"));
		uib_j("labels", strcat(labels, "]"));
	UIB_Close();
	if (strstrofs(nm, "^", 0) >= 0)
		UIB_Button("plain", _("Remove the colour codes"), UIB_A("player.name.plain", _("Remove the colour codes"), ""), "link");
	UIB_Close();

	UIB_Section("character", _("Character"), true);
	if (uib_pm_n > 0)
	{
		int shown = (cur >= 0) ? cur : 0;
		UIB_Open("portrait", "image");
			uib_s("ref", strcat("pk3:", uib_pm_model[shown], "_", uib_pm_skin[shown]));   // models/player/erebus.iqm_0.jpg
			uib_s("fit", "contain");
			uib_f("aspect", 1);
			uib_s("alt", uib_pm_title[shown]);
		UIB_Close();
		UIB_Open("flip", "row");
			uib_s("align", "spread");
			UIB_Button("prev", "<", UIB_A("player.model.prev", _("Previous model"), ""), "tonal");
			UIB_Text("title", uib_pm_title[shown], "title");
			UIB_Button("next", ">", UIB_A("player.model.next", _("Next model"), ""), "tonal");
		UIB_Close();
		string kind = uib_pm_up[shown] ? _("Your model") : _("Xonotic model");
		UIB_Text("kind", sprintf(_("%s, %d of %d"), kind, shown + 1, uib_pm_n), "caption");
		if (uib_pm_up[shown])
			UIB_Button("delete", _("Delete this model"),
				sprintf("{\"id\":\"player.model.delete\",\"label\":%s,\"icon\":\"delete\",\"confirm\":{\"title\":%s,\"body\":%s,\"ok\":%s,\"destructive\":true}}",
					uib_q(_("Delete this model")), uib_q(_("Delete this model?")), uib_q(_("The file is removed from this device. You can upload it again.")), uib_q(_("Delete"))),
				"destructive");
	}
	else
		UIB_Text("none", _("No player models found: the game data is not complete yet."), "caption");
	UIB_Close();

	UIB_Section("colours", _("Colours"), true);
	float c = cvar("_cl_color");
	UIB_Open("shirt", "colour");
		uib_s("label", _("Shirt"));
		uib_s("bind", "vm:player.shirt");
		uib_s("value", UIB_ColourHex(floor(c / 16)));
		uib_j("palette", UIB_Palette());
		UIB_Apply("reconnect");
	UIB_Close();
	UIB_Open("pants", "colour");
		uib_s("label", _("Pants"));
		uib_s("bind", "vm:player.pants");
		uib_s("value", UIB_ColourHex(c - 16 * floor(c / 16)));
		uib_j("palette", UIB_Palette());
		UIB_Apply("reconnect");
	UIB_Close();
	UIB_Close();

	if (cvar_string("uib_pm") != "")
	{
		UIB_Section("upload", _("Your own model"), true);
		UIB_Button("pick", _("Upload a model"), "{\"id\":\"player.upload\",\"label\":\"Choose a model file or .pk3\",\"icon\":\"upload\",\"kind\":\"file\",\"accept\":[\"pk3\",\"zip\"]}", "secondary");
		string msg = UIB_VM("player.upload.msg");
		if (msg != "")
			UIB_Text("result", msg, (UIB_VM("player.upload.ok") == "1") ? "caption" : "warning");
		UIB_Text("hint", _("A .pk3 or .zip with the model (iqm, dpm, md3 or zym), its skin and animations; it becomes your character when it fits. Other players see it only if they have the same model."), "caption");
		UIB_Close();
	}
}

string UIB_PMPayloadPath(string payload)
{
	int k = strstrofs(payload, "\"path\":\"", 0);
	if (k < 0) return "";
	string path = substring(payload, k + 8, -1);
	return substring(path, 0, strstrofs(path, "\"", 0));
}

bool UIB_PlayerAction(string a, string payload)
{
	if (a == "player.model.prev" || a == "player.model.next")
	{
		UIB_PMLoad();
		if (uib_pm_n < 1) return true;
		int cur = UIB_PMCurrent();
		int i = (cur < 0) ? 0 : mod(cur + ((a == "player.model.next") ? 1 : uib_pm_n - 1), uib_pm_n);
		UIB_PMSelect(i);
		UIB_RebuildAll();
		return true;
	}
	if (a == "player.model.delete")
	{
		UIB_PMLoad();
		int cur = UIB_PMCurrent();
		if (cur >= 0 && uib_pm_up[cur] && uib_pm_delete(uib_pm_model[cur]))
		{
			uib_pm_n = -1;
			UIB_PMLoad();
			if (uib_pm_n > 0) UIB_PMSelect(0);
			UIB_VMSet("player.upload.msg", "");
			UIB_RebuildAll();
		}
		return true;
	}
	if (a == "player.upload")
	{
		string path = UIB_PMPayloadPath(payload);
		if (path == "") return true;
		if (uib_pm_import(path))
		{
			tokenizebyseparator(uib_pm_report(), "\t");
			string m = argv(1), s = argv(2), t = argv(3);
			uib_pm_n = -1;
			UIB_PMLoad();
			cvar_set("_cl_playermodel", m);
			cvar_set("_cl_playerskin", s);
			localcmd("\nplayermodel $_cl_playermodel; playerskin $_cl_playerskin\nsaveconfig\n");
			UIB_VMSet("player.upload.ok", "1");
			UIB_VMSet("player.upload.msg", sprintf(_("%s fits and is now your character."), t));
		}
		else
		{
			tokenizebyseparator(uib_pm_report(), "\t");
			UIB_VMSet("player.upload.ok", "0");
			UIB_VMSet("player.upload.msg", sprintf(_("Not used: %s"), argv(1)));
		}
		UIB_RebuildAll();
		return true;
	}
	if (a == "player.name.plain")
	{
		string nm = strdecolorize(cvar_string("_cl_name"));
		cvar_set("_cl_name", nm);
		UIB_VMSet("player.name", nm);
		localcmd("\nname \"$_cl_name\"\nsaveconfig\n");
		UIB_RebuildAll();
		return true;
	}
	return false;
}

// a tap on a name colour: the code goes at the end of the name
bool UIB_PlayerNameColour(string hex)
{
	for (int i = 0; i < 10; ++i)
		if (UIB_PMNameHex(i) == hex)
		{
			string nm = strcat(cvar_string("_cl_name"), "^", ftos(i));
			cvar_set("_cl_name", nm);
			UIB_VMSet("player.name", nm);
			localcmd("\nname \"$_cl_name\"\nsaveconfig\n");
			UIB_RebuildAll();
			return true;
		}
	return false;
}
