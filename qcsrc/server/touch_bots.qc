// Godnotic: "sv_cmd touchbots <count> [team]", what the touch Server control screen sends.
// Sets the bot count AT ONCE (the stock bot_number only adds one bot per server frame and
// leaves team placement to the balancer) and, in a team game, puts the bots it adds on the
// team asked for (red, blue, yellow, pink; empty or "auto" leaves them to the balancer).
// A server without this command just ignores it: the screen also sends the stock bot_number.

.bool touch_botold;

void GameCommand_touchbots(int request, int argc)
{
	switch (request)
	{
		case CMD_REQUEST_COMMAND:
		{
			if (argc < 2 || !world_initialized)
				break;
			int want = bound(0, floor(stof(argv(1))), 64);
			string dest = argv(2);
			FOREACH_CLIENT(IS_BOT_CLIENT(it), { it.touch_botold = true; });
			cvar_settemp("bot_vs_human", "0");
			cvar_settemp("minplayers", "0");
			cvar_settemp("minplayers_per_team", "0");
			cvar_settemp("bot_number", ftos(want));
			bool full = !bot_fixcount(true);
			int added = 0, moved = 0;
			if (teamplay && dest != "" && dest != "auto")
			{
				int team_num = Team_ColorToTeam(dest);
				int team_id = Team_TeamToIndex(team_num);
				if (team_num && team_id != -1 && (teamplay_bitmask & Team_TeamToBit(team_num)))
				{
					FOREACH_CLIENT(IS_BOT_CLIENT(it) && !it.touch_botold, {
						++added;
						if (it.team == team_num || MoveToTeam(it, team_id, 6))
							++moved;
					});
				}
			}
			int bots = 0, red = 0, blue = 0, yellow = 0, pink = 0;
			FOREACH_CLIENT(IS_BOT_CLIENT(it), {
				it.touch_botold = false;
				++bots;
				if (it.team == NUM_TEAM_1) ++red;
				else if (it.team == NUM_TEAM_2) ++blue;
				else if (it.team == NUM_TEAM_3) ++yellow;
				else if (it.team == NUM_TEAM_4) ++pink;
			});
			LOG_INFOF("touchbots: want=%d bots=%d full=%d moved=%d red=%d blue=%d yellow=%d pink=%d",
				want, bots, full, moved, red, blue, yellow, pink);
			return;
		}
		default:
		case CMD_REQUEST_USAGE:
			break;
	}
	LOG_HELP("Usage:^3 sv_cmd touchbots <count> [red|blue|yellow|pink|auto]");
}

SERVER_COMMAND(touchbots, "Set the bot count at once, optionally on one team (touch Server control)") { GameCommand_touchbots(request, arguments); }
