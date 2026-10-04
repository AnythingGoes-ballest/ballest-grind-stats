// Grind Stats: how long you've spent on every map, how often you restarted it, and where you get stuck.
//
// For each map (the game's own tracks and every workshop or local map), kept across launches:
//   time         all the time the map was on screen: racing, the pre-race menu and the pause menu too (not while
//                a replay is watched, and not in the track editor)
//   restarts     restarts from the beginning (Backspace, or R before the first checkpoint)
//   respawns     R at a checkpoint, counted for that checkpoint
//   falls        falls into the kill zone, counted for the checkpoint the ball goes back to (or the start)
//   finishes     runs finished
//   played       time actually racing: the race running, the game not paused, and the ball steered or jumped in the
//                last IDLE_AFTER seconds (Trackmania Grinding Stats' idle rule)
//   attempts     runs started: the first start and every restart
// The card shows this map's played time, attempts and finishes, all-time and for this session (since the map was
// loaded; a restart doesn't start a new one, leaving the track ends it). Settings add rows for the map's name, its
// time on the map, restarts, respawns, falls (each with this session's count) and the checkpoint you're on. F6 hides
// and shows it until the game closes, F8 writes the map's numbers to the log.
// Checkpoints are numbered in the order you first reached them and recognised by where they are, so a checkpoint keeps
// its number between sessions. Everything comes from the game (Race::Restarts, Respawns, Falls, CurrentCheckpoint,
// RunId for a new run, IsPaused, and GetInput for steering and jumping), not from key presses, so rebinding keys
// changes nothing.
//
// The card can be dragged while the cursor is on screen. The
// "grind stats" footer button opens every map's stats with the totals; a map's "details" shows its checkpoints.

// ShowOverlay and OverlaySize keep their names from 0.1, so a saved choice still applies.
[Setting name="Show card" description="The card with this map's numbers while you play; stats keep counting either way"]
bool ShowOverlay = true;

[Setting name="Card size" min=12 max=48 description="Height of the card's numbers, in pixels"]
float OverlaySize = 15;

[Setting name="Background" min=0 max=1 description="How dark the box behind the card is (0: none)"]
float BackgroundOpacity = 0.72f;

// Extra rows for the card, all off by default.
[Setting name="Show map name" description="A MAP row above the others"]
bool ShowMapName = false;

[Setting name="Show time on the map" description="All the time the map was on screen, menus and pause included"]
bool ShowOnMap = false;

[Setting name="Show restarts"]
bool ShowRestarts = false;

[Setting name="Show respawns"]
bool ShowRespawns = false;

[Setting name="Show falls"]
bool ShowFalls = false;

[Setting name="Show checkpoint" description="Respawns and falls at the checkpoint you're on, on maps that have checkpoints"]
bool ShowCheckpoint = false;

// Colours (linear, as the widgets take them), the same as the ghost viewer's.
const float WINDOW_R = 0.0052f, WINDOW_G = 0.0060f, WINDOW_B = 0.0086f;     // #101217
const float CARD_R = 0.0116f, CARD_G = 0.0137f, CARD_B = 0.0194f;           // #1c1f26
const float BUTTON_R = 0.0232f, BUTTON_G = 0.0273f, BUTTON_B = 0.0382f;     // #2a2e37
const float PRIMARY_R = 0.0782f, PRIMARY_G = 0.2051f, PRIMARY_B = 0.0048f;  // #4f7d0f
const float MUTED_R = 0.2582f, MUTED_G = 0.2747f, MUTED_B = 0.3185f;        // #8b8f99
const float WARN_R = 0.8879f, WARN_G = 0.5333f, WARN_B = 0.0762f;           // #f2c14e
const float GREEN_R = 0.235f, GREEN_G = 1.0f, GREEN_B = 0.353f;             // the grind timer's green
const float LIME_R = 0.80f, LIME_G = 1.0f, LIME_B = 0.0f;                   // the game's menu highlight: this session

// The card, as the UE4SS Grind Stats mod drew it.
const string CARD_FONT = "/Game/UI/Fonts/CocogoosePro.CocogoosePro";     // the game's menu font
const float BOX_R = 0.08f, BOX_G = 0.08f, BOX_B = 0.09f;    // the box behind it, at the Background setting's opacity
const float LABEL_SCALE = 0.8f;         // the labels against the numbers
const float LABEL_ALPHA = 0.65f;        // the labels are white, this opaque
const float VALUE_GAP = 18;             // pixels from the label to the number
const float DELTA_GAP = 10;             // and from the number to this session's
const float CARD_PAD_X = 14, CARD_PAD_Y = 8;
const float CARD_X = 40, CARD_Y = 110;  // below the game's pause-screen PB box
const double IDLE_AFTER = 5.0;          // seconds without steering or jumping before played time stops

const double SAVE_EVERY = 5.0;          // seconds
const double SAME_PLACE = 100;          // cm: a checkpoint this close to a known one is that one
const float THUMB_W = 160, THUMB_H = 90;
const float BIG_W = 320, BIG_H = 180;

// --- the numbers ------------------------------------------------------------------------------------------------------

class Checkpoint
{
    double x = 0;
    double y = 0;
    double z = 0;
    int respawns = 0;
    int falls = 0;
}

class MapStats
{
    string key;                         // Race::TrackKey
    string name;
    string author;
    string image;                       // Race::TrackImage
    bool custom = false;
    double seconds = 0;
    int restarts = 0;
    int respawns = 0;
    int falls = 0;
    int fallsAtStart = 0;               // falls before the first checkpoint (back to the start)
    int restartsAtStart = 0;            // restarts before the first checkpoint
    int finishes = 0;
    double played = 0;                  // seconds actually racing (see the top)
    int attempts = 0;                   // runs started
    int checkpointTotal = 0;            // how many the map has
    int lastPlayed = 0;                 // bigger is more recent
    array<Checkpoint@> checkpoints;     // in the order first reached
    bool dirty = false;
}

array<MapStats@> maps;
int playCounter = 0;
bool indexDirty = false;

MapStats@ current;                      // the map on screen, or null
int seenRestarts = 0, seenRespawns = 0, seenFalls = 0;
// A finish: the race stops (bRaceActive goes false) while it counts as complete, and the game takes the ball away
// (EndRaceSequence un-possesses it: the run id goes to -1). Read from the game's Blueprints (BP_TrackManager,
// BP_MyPlayerController): bRaceComplete is only ever set at a finish and stays true until the map is loaded again, so
// it can't tell one finish from the next; a restart also stops the race but keeps the ball.
const double FINISH_WAIT = 1.5;         // seconds after the race stops for the ball to be taken away
bool wasActive = false;
double finishUntil = 0;                 // while the race has stopped complete: until when a finish may still be seen
MapStats@ finishMap;                    // the map it stopped on
int seenCheckpoint = -1;
double lastTick = 0, lastSave = 0;

// This session: since the map on the track was loaded. A restart keeps it; leaving the track ends it. Its numbers are
// the map's now less the map's when it started.
class Session
{
    string key;                         // Race::TrackKey, "" off a track
    MapStats@ start;                    // a copy of the map's numbers on its first counted frame, null before
}
Session@ session = Session();
int countedRun = -1;                    // the Race::RunId last counted as an attempt
double lastInput = 0;                   // when the ball was last steered or jumped
bool hiddenByKey = false;               // F6

// --- the windows ------------------------------------------------------------------------------------------------------

UI::FooterButton@ footer;
UI::Window@ card;

// What a card row shows: one of a map's numbers, and whether its setting wants the row.
funcdef double Stat(MapStats@ m);
funcdef bool Wanted();

double Played(MapStats@ m) { return m.played; }
double Attempts(MapStats@ m) { return m.attempts; }
double Finishes(MapStats@ m) { return m.finishes; }
double OnMap(MapStats@ m) { return m.seconds; }
double Restarts(MapStats@ m) { return m.restarts; }
double Respawns(MapStats@ m) { return m.respawns; }
double Falls(MapStats@ m) { return m.falls; }

bool Always() { return true; }
bool WantMapName() { return ShowMapName; }
bool WantOnMap() { return ShowOnMap; }
bool WantRestarts() { return ShowRestarts; }
bool WantRespawns() { return ShowRespawns; }
bool WantFalls() { return ShowFalls; }

// A row of the card: its label, then the map's all-time number and this session's in lime ("+41"), or only one of
// them. Hidden rows take no room, so the card closes up.
const int ALL_TIME = 1, THIS_SESSION = 2, BOTH = 3;
class CardRow
{
    string label;
    Stat@ stat;                         // null for MAP and CHECKPOINT, which fill their own texts
    int shows = BOTH;
    bool time = false;                  // M:SS rather than a count
    Wanted@ wanted;
    UI::Text@ labelText;
    UI::Text@ value;
    UI::Text@ delta;                    // null unless the row shows BOTH
    array<UI::Text@> parts;
    bool shown = true;

    CardRow() {}
    CardRow(const string &in label, Stat@ stat, int shows, bool time, Wanted@ wanted)
    {
        this.label = label;
        @this.stat = stat;
        this.shows = shows;
        this.time = time;
        @this.wanted = wanted;
    }

    void Show(bool on)
    {
        if (on == shown)
            return;
        shown = on;
        for (uint i = 0; i < parts.length(); i++)
            parts[i].visible = on;
    }

    string Format(double n) { return time ? ShortTime(n) : "" + int(n); }

    // The map's numbers, all-time and this session.
    double AllTime(MapStats@ m) { return stat(m); }
    double ThisSession(MapStats@ m) { return session.start is null || session.key != m.key ? 0 : stat(m) - stat(session.start); }

    void Fill(MapStats@ m)
    {
        if (shows == THIS_SESSION)
            value.text = Format(ThisSession(m));
        else
            value.text = Format(AllTime(m));
        if (delta !is null)
            delta.text = "+" + Format(ThisSession(m));
    }

    // "attempts 318 (+41)", for the log.
    string Line(MapStats@ m)
    {
        string text = Lower(label) + " ";
        if (shows == THIS_SESSION)
            return text + Format(ThisSession(m));
        text += Format(AllTime(m));
        return shows == BOTH ? text + " (+" + Format(ThisSession(m)) + ")" : text;
    }
}

// Top to bottom, between MAP and CHECKPOINT.
array<CardRow@> cardRows = {
    CardRow("TOTAL", @Played, ALL_TIME, true, @Always),
    CardRow("SESSION", @Played, THIS_SESSION, true, @Always),
    CardRow("ATTEMPTS", @Attempts, BOTH, false, @Always),
    CardRow("FINISHES", @Finishes, BOTH, false, @Always),
    CardRow("ON MAP", @OnMap, ALL_TIME, true, @WantOnMap),
    CardRow("RESTARTS", @Restarts, BOTH, false, @WantRestarts),
    CardRow("RESPAWNS", @Respawns, BOTH, false, @WantRespawns),
    CardRow("FALLS", @Falls, BOTH, false, @WantFalls)
};
CardRow mapRow, checkpointRow;
UI::Text@ checkpointDetail;
array<UI::Text@> cardLabels;
array<UI::Text@> cardValues;            // sized from Card size, as the labels are from it times LABEL_SCALE

UI::Window@ stats;
int listView = 0, detailView = 0;
UI::Button@ closeButton;
array<UI::Button@> sortButtons;
int sortMode = 0;                       // 0 time, 1 restarts, 2 recent, 3 name
const array<string> SORT_NAMES = {"most time", "most restarts", "recent", "a-z"};
array<UI::Button@> detailButtons;
array<MapStats@> listed;                // the maps in the list, in the order shown
MapStats@ detailed;                     // the map whose details are shown, or null
UI::Button@ backButton;
UI::Button@ resetButton;
double resetArmedUntil = 0;

void Main()
{
    Load();
    seenRestarts = Race::Restarts();
    seenRespawns = Race::Respawns();
    seenFalls = Race::Falls();
    wasActive = Race::IsActive();
    lastTick = lastSave = lastInput = Host::Time();

    @footer = UI::AddFooterButton("grind stats");
    BuildCard();
    BuildStats();
    Log::Info("grind stats: " + maps.length() + " map(s), " + TimeText(TotalSeconds()) + " in all");
}

// --- saving -----------------------------------------------------------------------------------------------------------
// Storage keeps one line per key: "maps" lists every map's key (joined by '|'), "m:<key>" a map's numbers (played,
// attempts and restarts before the first checkpoint were added at the end in 0.2.0, so a 0.1 file still loads) and
// "c:<key>" its checkpoints ("x,y,z,respawns,falls" joined by ';'). Keys can't hold '=' (the file's separator), names
// can't hold tabs, '|' or line breaks: those are replaced.

string Replace(const string &in text, const string &in what, const string &in with)
{
    string result = "";
    uint from = 0;
    while (true)
    {
        int at = text.findFirst(what, from);
        if (at < 0)
            break;
        result += text.substr(from, uint(at) - from) + with;
        from = uint(at) + what.length();
    }
    return result + text.substr(from);
}

string StorageKey(const string &in trackKey) { return Replace(Replace(trackKey, "=", "%3D"), "|", "%7C"); }

string Clean(const string &in text) { return Replace(Replace(Replace(Replace(text, "\t", " "), "\n", " "), "\r", " "), "|", "/"); }

string Joined(const array<string> &in parts, const string &in with)
{
    string result = "";
    for (uint i = 0; i < parts.length(); i++)
        result += (i > 0 ? with : "") + parts[i];
    return result;
}

void Load()
{
    playCounter = int(parseInt(Storage::Get("plays", "0")));
    string index = Storage::Get("maps", "");
    if (index == "")
        return;
    array<string>@ keys = index.split("|");
    for (uint i = 0; i < keys.length(); i++)
    {
        array<string>@ f = Storage::Get("m:" + keys[i], "").split("\t");
        if (f.length() < 13 || f[0] != "1")
            continue;
        MapStats m;
        m.key = Replace(Replace(keys[i], "%7C", "|"), "%3D", "=");
        m.name = f[1];
        m.author = f[2];
        m.image = f[3];
        m.custom = f[4] == "1";
        m.seconds = parseFloat(f[5]);
        m.restarts = int(parseInt(f[6]));
        m.respawns = int(parseInt(f[7]));
        m.falls = int(parseInt(f[8]));
        m.fallsAtStart = int(parseInt(f[9]));
        m.finishes = int(parseInt(f[10]));
        m.checkpointTotal = int(parseInt(f[11]));
        m.lastPlayed = int(parseInt(f[12]));
        if (f.length() >= 15)               // added in 0.2.0 without a new record version: the length tells them apart
        {
            m.played = parseFloat(f[13]);
            m.attempts = int(parseInt(f[14]));
        }
        if (f.length() >= 16)
            m.restartsAtStart = int(parseInt(f[15]));
        string cps = Storage::Get("c:" + keys[i], "");
        if (cps != "")
        {
            array<string>@ list = cps.split(";");
            for (uint c = 0; c < list.length(); c++)
            {
                array<string>@ v = list[c].split(",");
                if (v.length() < 5)
                    continue;
                Checkpoint cp;
                cp.x = parseFloat(v[0]);
                cp.y = parseFloat(v[1]);
                cp.z = parseFloat(v[2]);
                cp.respawns = int(parseInt(v[3]));
                cp.falls = int(parseInt(v[4]));
                m.checkpoints.insertLast(cp);
            }
        }
        maps.insertLast(m);
    }
}

void Save()
{
    for (uint i = 0; i < maps.length(); i++)
    {
        MapStats@ m = maps[i];
        if (!m.dirty)
            continue;
        array<string> f = {"1", Clean(m.name), Clean(m.author), Clean(m.image), m.custom ? "1" : "0", formatFloat(m.seconds, "", 0, 1),
                           "" + m.restarts, "" + m.respawns, "" + m.falls, "" + m.fallsAtStart, "" + m.finishes, "" + m.checkpointTotal,
                           "" + m.lastPlayed, formatFloat(m.played, "", 0, 1), "" + m.attempts,
                           "" + m.restartsAtStart};
        Storage::Set("m:" + StorageKey(m.key), Joined(f, "\t"));
        array<string> cps;
        for (uint c = 0; c < m.checkpoints.length(); c++)
        {
            Checkpoint@ cp = m.checkpoints[c];
            cps.insertLast(int(cp.x) + "," + int(cp.y) + "," + int(cp.z) + "," + cp.respawns + "," + cp.falls);
        }
        Storage::Set("c:" + StorageKey(m.key), Joined(cps, ";"));
        m.dirty = false;
    }
    if (indexDirty)
    {
        array<string> keys;
        for (uint i = 0; i < maps.length(); i++)
            keys.insertLast(StorageKey(maps[i].key));
        Storage::Set("maps", Joined(keys, "|"));
        Storage::Set("plays", "" + playCounter);
        indexDirty = false;
    }
    lastSave = Host::Time();
}

// --- counting ---------------------------------------------------------------------------------------------------------

// A map is counted while it's on screen to be played: not in the track editor (its test runs included), not while a
// replay is watched.
bool Counting()
{
    if (!Race::OnTrack() || Replay::IsActive() || Editor::IsOpen())
        return false;
    string key = Race::TrackKey();
    return key != "" && key.findFirst("LevelEditor") < 0;
}

MapStats@ Find(const string &in key)
{
    for (uint i = 0; i < maps.length(); i++)
        if (maps[i].key == key)
            return maps[i];
    return null;
}

void Enter(const string &in key)
{
    @current = Find(key);
    if (current is null)
    {
        MapStats m;
        m.key = key;
        maps.insertLast(m);
        @current = m;
        indexDirty = true;
        Log::Info("grind stats: first time on " + key);
    }
    TakeOldCounts(current);
    current.lastPlayed = ++playCounter;
    current.custom = Race::IsCustomTrack();
    current.dirty = true;
    indexDirty = true;
    seenCheckpoint = -1;
}

// Will's Grind Stats 0.1 kept "track:<key>" = "played attempts finishes" in the same storage: added once, then
// cleared.
void TakeOldCounts(MapStats@ m)
{
    array<string>@ old = Storage::Get("track:" + m.key, "").split(" ");
    if (old.length() != 3)
        return;
    m.played += parseFloat(old[0]);
    m.attempts += int(parseInt(old[1]));
    m.finishes += int(parseInt(old[2]));
    Storage::Set("track:" + m.key, "");
    m.dirty = true;
}

// The track's name, author and picture, which the game fills in a moment after the map appears.
void ReadTrack(MapStats@ m)
{
    string name = m.custom ? Race::TrackName() : OfficialTitle(m.key.substr(4));
    string author = m.custom ? Race::TrackAuthor() : "";
    string image = Race::TrackImage();
    if (name != "" && name != m.name)
    {
        m.name = name;
        m.dirty = true;
    }
    if (author != m.author)
    {
        m.author = author;
        m.dirty = true;
    }
    if (image != "" && image != m.image)
    {
        m.image = image;
        m.dirty = true;
    }
    int total = Race::CheckpointCount();
    if (total != m.checkpointTotal && total > 0)
    {
        m.checkpointTotal = total;
        m.dirty = true;
    }
}

// The checkpoint at the game's index `index`, as this map's own (numbered by first reach), added the first time.
Checkpoint@ Known(MapStats@ m, int index)
{
    double x, y, z;
    if (!Race::CheckpointPosition(index, x, y, z))
        return null;
    for (uint i = 0; i < m.checkpoints.length(); i++)
    {
        Checkpoint@ cp = m.checkpoints[i];
        if (Math::abs(cp.x - x) < SAME_PLACE && Math::abs(cp.y - y) < SAME_PLACE && Math::abs(cp.z - z) < SAME_PLACE)
            return cp;
    }
    Checkpoint cp;
    cp.x = x;
    cp.y = y;
    cp.z = z;
    m.checkpoints.insertLast(cp);
    m.dirty = true;
    return cp;
}

int NumberOf(MapStats@ m, Checkpoint@ cp)
{
    for (uint i = 0; i < m.checkpoints.length(); i++)
        if (m.checkpoints[i] is cp)
            return int(i) + 1;
    return 0;
}

// A new map on the track, or the same one loaded again, starts a new session. Keyed off the track rather than Enter(),
// which also runs again after watching a replay or leaving the editor.
void FollowSession()
{
    string key = Race::OnTrack() ? Race::TrackKey() : "";
    if (key == session.key)
        return;
    @session = Session();
    session.key = key;
    countedRun = -1;
    lastInput = 0;                      // idle until the ball is steered or jumped
}

void StartSession(MapStats@ m)
{
    MapStats start = m;
    @session.start = start;
}

// Time only counts as played while the ball is being steered or jumped, as in Grinding Stats.
void FollowInput()
{
    double x, y;
    bool jump;
    if (Race::GetInput(x, y, jump) && (x != 0 || y != 0 || jump))
        lastInput = Host::Time();
}

void Count(double step)
{
    int restarts = Race::Restarts(), respawns = Race::Respawns(), falls = Race::Falls();
    bool complete = Race::IsComplete(), active = Race::IsActive();
    if (Counting())
    {
        string key = Race::TrackKey();
        if (current is null || current.key != key)
            Enter(key);
        if (session.start is null && session.key == key)
            StartSession(current);
        ReadTrack(current);
        current.seconds += step;
        current.dirty = true;
        int index = Race::CurrentCheckpoint();
        Checkpoint@ cp = index >= 0 ? Known(current, index) : null;
        if (restarts > seenRestarts)
        {
            current.restarts += restarts - seenRestarts;
            if (seenCheckpoint < 0)         // where the ball was before the restart put it back
                current.restartsAtStart += restarts - seenRestarts;
        }
        if (respawns > seenRespawns)
        {
            current.respawns += respawns - seenRespawns;
            if (cp !is null)
                cp.respawns += respawns - seenRespawns;
        }
        if (falls > seenFalls)
        {
            current.falls += falls - seenFalls;
            if (cp !is null)
                cp.falls += falls - seenFalls;
            else
                current.fallsAtStart += falls - seenFalls;
        }
        if (wasActive && !active && complete)
        {
            finishUntil = Host::Time() + FINISH_WAIT;
            @finishMap = current;
        }
        int run = Race::RunId();
        if (active && run >= 0 && run != countedRun)
        {
            countedRun = run;
            current.attempts++;
        }
        if (active && !Race::IsPaused() && Host::Time() - lastInput <= IDLE_AFTER)
            current.played += step;
        seenCheckpoint = index;
    }
    else if (current !is null)
    {
        @current = null;
        Save();
    }
    // checked whether or not this frame counts, so a view the game switches to after the finish doesn't hide it
    if (finishUntil > 0)
    {
        if (Race::RunId() < 0 && finishMap !is null)
        {
            finishMap.finishes++;
            finishMap.dirty = true;
            finishUntil = 0;
        }
        else if (Host::Time() > finishUntil)
            finishUntil = 0;                // the ball stayed: a restart, not a finish
    }
    seenRestarts = restarts;
    seenRespawns = respawns;
    seenFalls = falls;
    wasActive = active;
}

// --- text -------------------------------------------------------------------------------------------------------------

// H:MM:SS
string TimeText(double seconds)
{
    int total = int(seconds);
    return (total / 3600) + ":" + formatInt((total / 60) % 60, "0", 2) + ":" + formatInt(total % 60, "0", 2);
}

string Plural(int n, const string &in word) { return n + " " + word + (n == 1 ? "" : "s"); }

string Short(const string &in text, uint most) { return text.length() <= most ? text : text.substr(0, most - 3) + "..."; }

string Lower(const string &in text)
{
    string result = text;
    for (uint i = 0; i < result.length(); i++)
        if (result[i] >= 65 && result[i] <= 90)
            result[i] = result[i] + 32;
    return result;
}

bool AllDigits(const string &in text)
{
    for (uint i = 0; i < text.length(); i++)
        if (text[i] < 48 || text[i] > 57)
            return false;
    return text.length() > 0;
}

// "BigStairs" reads as "Big Stairs".
string Words(const string &in camel)
{
    string result = "";
    for (uint i = 0; i < camel.length(); i++)
    {
        if (i > 0 && camel[i] >= 65 && camel[i] <= 90 && camel[i - 1] >= 97 && camel[i - 1] <= 122)
            result += " ";
        result += camel.substr(i, 1);
    }
    return result;
}

// The game's tracks by the name the ghost viewer gives them: the circuit's by number and name ("06  Loopworks"),
// the others by their title or level ("Leth Trial 01").
string OfficialTitle(const string &in level)
{
    string title = Tracks::Title(level);
    if (title == "" || level.findFirst("Map_LethTrial") == 0)
    {
        title = level.findFirst("Map_") == 0 ? level.substr(4) : level;
        return Words(Replace(title, "_", " "));
    }
    if (!AllDigits(title))
        return title;
    if (level.findFirst("Map_Track_S") == 0)
    {
        int cut = level.findFirst("_", 11);
        if (cut > 0)
            return title + "  " + Words(level.substr(cut + 1));
    }
    return "Track " + title;
}

double TotalSeconds()
{
    double total = 0;
    for (uint i = 0; i < maps.length(); i++)
        total += maps[i].seconds;
    return total;
}

UI::Text@ Muted(UI::Text@ t)
{
    t.SetColor(MUTED_R, MUTED_G, MUTED_B, 1);
    return t;
}

void Secondary(UI::Button@ b) { b.SetBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1); }
void Primary(UI::Button@ b) { b.SetBackground(PRIMARY_R, PRIMARY_G, PRIMARY_B, 1); }

// --- the card -------------------------------------------------------------------------------------------------------
//   MAP         Chaos2                       (Show map name)
//   TOTAL       1:42:17                      played on this map, all-time
//   SESSION     12:05                        played since the map was loaded
//   ATTEMPTS    318  +41                     runs started, all-time and (lime) this session
//   FINISHES    27   +3                      runs finished
//   ON MAP      0:42:17                      (Show time on the map)
//   RESTARTS    36   +4                      (Show restarts)
//   RESPAWNS    120  +9                      (Show respawns)
//   FALLS       12   +1                      (Show falls)
//   CHECKPOINT  3    14 respawns, 2 falls    (Show checkpoint; only on maps with checkpoints)
// In the game's own menu font, labels filling the row so the numbers sit against the right edge, rows touching.

UI::Text@ CardText(CardRow@ row, float size, array<UI::Text@>@ sizedWith)
{
    UI::Text@ t = card.AddText("", size);
    t.SetFont(CARD_FONT);
    row.parts.insertLast(t);
    sizedWith.insertLast(t);
    return t;
}

UI::Text@ CardLabel(CardRow@ row, const string &in text)
{
    UI::Text@ t = CardText(row, OverlaySize * LABEL_SCALE, cardLabels);
    t.text = text;
    t.SetColor(1, 1, 1, LABEL_ALPHA);
    t.SetFill(true);
    return t;
}

UI::Text@ CardValue(CardRow@ row)
{
    UI::Text@ t = CardText(row, OverlaySize, cardValues);
    t.SetGapBefore(VALUE_GAP);
    return t;
}

UI::Text@ CardDelta(CardRow@ row)
{
    UI::Text@ t = CardText(row, OverlaySize, cardValues);
    t.SetColor(LIME_R, LIME_G, LIME_B, 1);
    t.SetGapBefore(DELTA_GAP);
    return t;
}

void BuildCard()
{
    @card = UI::CreateWindow();
    card.SetAnchor(0, 0);
    card.SetPivot(0, 0);
    card.SetOffset(CARD_X, CARD_Y);
    card.SetPadding(CARD_PAD_X, CARD_PAD_Y);
    card.SetRowGap(0);
    card.visible = false;
    @mapRow.labelText = CardLabel(mapRow, "MAP");
    @mapRow.value = CardValue(mapRow);
    for (uint i = 0; i < cardRows.length(); i++)
    {
        CardRow@ row = cardRows[i];
        card.NewRow();
        @row.labelText = CardLabel(row, row.label);
        @row.value = CardValue(row);
        if (row.shows == BOTH)
            @row.delta = CardDelta(row);
    }
    card.NewRow();
    @checkpointRow.labelText = CardLabel(checkpointRow, "CHECKPOINT");
    @checkpointRow.value = CardValue(checkpointRow);
    @checkpointDetail = CardText(checkpointRow, OverlaySize * LABEL_SCALE, cardLabels);   // a dim note, not filling
    checkpointDetail.SetColor(1, 1, 1, LABEL_ALPHA);
    checkpointDetail.SetGapBefore(DELTA_GAP);
    card.movable = true;                // after SetOffset: that is where "reset position" puts it back
    OnSettingsChanged();
}

// The plugin manager changed a setting.
void OnSettingsChanged()
{
    for (uint i = 0; i < cardLabels.length(); i++)
        cardLabels[i].size = OverlaySize * LABEL_SCALE;
    for (uint i = 0; i < cardValues.length(); i++)
        cardValues[i].size = OverlaySize;
    card.SetBackground(BOX_R, BOX_G, BOX_B, BackgroundOpacity);
    mapRow.Show(ShowMapName);
    for (uint i = 0; i < cardRows.length(); i++)
        cardRows[i].Show(cardRows[i].wanted());
    checkpointRow.Show(ShowCheckpoint && current !is null && current.checkpointTotal > 0);
}

// M:SS, or H:MM:SS from an hour
string ShortTime(double seconds)
{
    int s = int(seconds);
    if (s >= 3600)
        return TimeText(seconds);
    return (s / 60) + ":" + formatInt(s % 60, "0", 2);
}

void UpdateCard()
{
    if (Input::Pressed(Input::F6))
        hiddenByKey = !hiddenByKey;
    if (Input::Pressed(Input::F8))
        Report();
    card.visible = ShowOverlay && !hiddenByKey && current !is null;
    if (!card.visible)
        return;
    if (mapRow.shown)
        mapRow.value.text = Short(current.name, 28);
    for (uint i = 0; i < cardRows.length(); i++)
        if (cardRows[i].shown)
            cardRows[i].Fill(current);
    // Only on maps that have checkpoints: before the first one, the restarts and the falls back to the start.
    checkpointRow.Show(ShowCheckpoint && current.checkpointTotal > 0);
    if (!checkpointRow.shown)
        return;
    Checkpoint@ cp = seenCheckpoint >= 0 ? Known(current, seenCheckpoint) : null;
    if (cp is null)
    {
        checkpointRow.value.text = "START";
        checkpointDetail.text = Plural(current.restartsAtStart, "restart") + ", " + Plural(current.fallsAtStart, "fall");
    }
    else
    {
        checkpointRow.value.text = "" + NumberOf(current, cp);
        checkpointDetail.text = Plural(cp.respawns, "respawn") + ", " + Plural(cp.falls, "fall");
    }
}

// F8: this map's numbers in the log, every row whether shown or not.
void Report()
{
    if (current is null)
    {
        Log::Info("grind stats: not on a map");
        return;
    }
    string line = "grind stats: " + current.name;
    for (uint i = 0; i < cardRows.length(); i++)
        line += " | " + cardRows[i].Line(current);
    Log::Info(line);
}

// --- the stats window -------------------------------------------------------------------------------------------------
//   grind stats   [most time] [most restarts] [recent] [a-z]                                   [close]
//   +-------------------------------------------------------------------------------------------------+
//   | total time 12:03:44    restarts 830    respawns 2100    falls 310    finishes 57    maps 23    |
//   +-------------------------------------------------------------------------------------------------+
//   | [picture]  Chaos2              0:42:17    36 restarts   120 respawns   12 falls     [details]  |
//   |            by Action Jackson                                                                     |
//   +-------------------------------------------------------------------------------------------------+

void BuildStats()
{
    @stats = UI::CreateWindow();
    stats.SetScreenSize(0.72f, 0.8f);
    stats.SetBackground(WINDOW_R, WINDOW_G, WINDOW_B, 0.97f);
    stats.SetCardBackground(CARD_R, CARD_G, CARD_B, 1);
    stats.SetBlocksClicks(true);
    stats.zOrder = 450;
    stats.visible = false;
    stats.StartHeader();
    stats.AddText("grind stats", 28);
    stats.AddSpace(20);
    for (uint i = 0; i < SORT_NAMES.length(); i++)
        sortButtons.insertLast(stats.AddButton(SORT_NAMES[i]));
    stats.AddSpace(0);
    @closeButton = stats.AddButton("close");
    Secondary(closeButton);
    listView = stats.StartView();
    stats.SetScrolling(listView, true);
    detailView = stats.StartView();
    stats.SetScrolling(detailView, true);
    ShowSort();
}

void ShowSort()
{
    for (uint i = 0; i < sortButtons.length(); i++)
    {
        if (int(i) == sortMode)
            Primary(sortButtons[i]);
        else
            Secondary(sortButtons[i]);
    }
}

bool Before(MapStats@ a, MapStats@ b)
{
    if (sortMode == 0)
        return a.seconds > b.seconds;
    if (sortMode == 1)
        return a.restarts > b.restarts || (a.restarts == b.restarts && a.seconds > b.seconds);
    if (sortMode == 2)
        return a.lastPlayed > b.lastPlayed;
    return a.name < b.name;
}

void SortedMaps()
{
    listed.resize(0);
    for (uint i = 0; i < maps.length(); i++)
    {
        uint at = listed.length();
        while (at > 0 && Before(maps[i], listed[at - 1]))
            at--;
        listed.insertAt(at, maps[i]);
    }
}

UI::Text@ Column(const string &in text, float width, float size = 18)
{
    UI::Text@ t = stats.AddText(text, size);
    t.SetWidth(width);
    return t;
}

void BuildList()
{
    @detailed = null;
    stats.ClearView(listView);
    stats.ShowView(listView);
    int restarts = 0, respawns = 0, falls = 0, finishes = 0;
    for (uint i = 0; i < maps.length(); i++)
    {
        restarts += maps[i].restarts;
        respawns += maps[i].respawns;
        falls += maps[i].falls;
        finishes += maps[i].finishes;
    }
    stats.StartCard();
    Muted(stats.AddText("total time", 16));
    stats.AddSpace(8);
    UI::Text@ total = stats.AddText(TimeText(TotalSeconds()), 30);
    total.SetColor(GREEN_R, GREEN_G, GREEN_B, 1);
    stats.AddSpace(36);
    Muted(stats.AddText("restarts", 16));
    stats.AddText("" + restarts, 24);
    stats.AddSpace(28);
    Muted(stats.AddText("respawns", 16));
    stats.AddText("" + respawns, 24);
    stats.AddSpace(28);
    Muted(stats.AddText("falls", 16));
    stats.AddText("" + falls, 24);
    stats.AddSpace(28);
    Muted(stats.AddText("finishes", 16));
    stats.AddText("" + finishes, 24);
    stats.AddSpace(28);
    Muted(stats.AddText("maps", 16));
    stats.AddText("" + maps.length(), 24);
    stats.EndCard();

    detailButtons.resize(0);
    SortedMaps();
    stats.StartCard();
    if (listed.length() == 0)
        Muted(stats.AddText("play a map and its stats show up here", 16));
    else
    {
        stats.AddSpace(THUMB_W + 12);
        Muted(Column("map", 330, 14));
        Muted(Column("time", 130, 14));
        Muted(Column("restarts", 120, 14));
        Muted(Column("respawns", 120, 14));
        Muted(Column("falls", 100, 14));
        Muted(Column("finishes", 100, 14));
    }
    for (uint i = 0; i < listed.length(); i++)
    {
        MapStats@ m = listed[i];
        stats.NewRow();
        stats.AddImage(m.image, THUMB_W, THUMB_H);
        stats.AddSpace(12);
        Column(Short(m.name, 30) + (m.author != "" ? "\nby " + Short(m.author, 30) : ""), 330);
        Column(TimeText(m.seconds), 130);
        Column("" + m.restarts, 120);
        Column("" + m.respawns, 120);
        Column("" + m.falls, 100);
        Column("" + m.finishes, 100);
        UI::Button@ details = stats.AddButton("details");
        Primary(details);
        detailButtons.insertLast(details);
    }
    stats.EndCard();
    stats.ShowView(listView);
}

//   [back]  Chaos2  by Action Jackson                                                    [reset this map]
//   +-------------------------------------------------------------------------------------------------+
//   | [picture]   time 0:42:17   restarts 36   respawns 120   falls 12   finishes 3                  |
//   +-------------------------------------------------------------------------------------------------+
//   | checkpoint          respawns     falls                                                          |
//   | start                   -           4                                                          |
//   | 1                       12          1                                                          |
//   | 2  (most)               41          6                                                          |
//   | reached 7 of 11                                                                                  |
//   +-------------------------------------------------------------------------------------------------+
void BuildDetail(MapStats@ m)
{
    @detailed = m;
    resetArmedUntil = 0;
    stats.ClearView(detailView);
    stats.ShowView(detailView);
    stats.StartCard();
    @backButton = stats.AddButton("back");
    Secondary(backButton);
    stats.AddSpace(16);
    stats.AddText(m.name, 26);
    if (m.author != "")
    {
        stats.AddSpace(10);
        Muted(stats.AddText("by " + m.author, 18));
    }
    stats.AddSpace(0);
    @resetButton = stats.AddButton("reset this map");
    Secondary(resetButton);
    stats.NewRow();
    stats.AddImage(m.image, BIG_W, BIG_H);
    stats.AddSpace(24);
    stats.AddText("time\nrestarts\nrespawns\nfalls\nfinishes", 20).SetColor(MUTED_R, MUTED_G, MUTED_B, 1);
    stats.AddSpace(16);
    UI::Text@ values = stats.AddText(TimeText(m.seconds) + "\n" + m.restarts + "\n" + m.respawns + "\n" + m.falls + "\n" + m.finishes, 20);
    values.SetColor(GREEN_R, GREEN_G, GREEN_B, 1);
    stats.EndCard();

    stats.StartCard();
    if (m.checkpointTotal == 0 && m.checkpoints.length() == 0)
    {
        Muted(stats.AddText("this map has no checkpoints: every R restarts it from the beginning", 16));
        if (m.fallsAtStart > 0)
        {
            stats.NewRow();
            stats.AddText(Plural(m.fallsAtStart, "fall") + " back to the start", 18);
        }
    }
    else
    {
        // The checkpoint where the most went wrong stands out.
        int worst = -1, most = 0;
        for (uint i = 0; i < m.checkpoints.length(); i++)
            if (m.checkpoints[i].respawns + m.checkpoints[i].falls > most)
            {
                most = m.checkpoints[i].respawns + m.checkpoints[i].falls;
                worst = int(i);
            }
        Muted(Column("checkpoint", 180, 14));
        Muted(Column("respawns", 140, 14));
        Muted(Column("falls", 140, 14));
        stats.NewRow();
        Column("start", 180);
        Column(Plural(m.restartsAtStart, "restart"), 140);
        Column("" + m.fallsAtStart, 140);
        for (uint i = 0; i < m.checkpoints.length(); i++)
        {
            Checkpoint@ cp = m.checkpoints[i];
            stats.NewRow();
            UI::Text@ number = Column("" + (i + 1) + (int(i) == worst ? "   most" : ""), 180);
            UI::Text@ r = Column("" + cp.respawns, 140);
            UI::Text@ f = Column("" + cp.falls, 140);
            if (int(i) == worst)
            {
                number.SetColor(WARN_R, WARN_G, WARN_B, 1);
                r.SetColor(WARN_R, WARN_G, WARN_B, 1);
                f.SetColor(WARN_R, WARN_G, WARN_B, 1);
            }
        }
        stats.NewRow();
        Muted(stats.AddText("reached " + m.checkpoints.length() + " of " + m.checkpointTotal + " checkpoints; numbered in the order you first reached them", 14));
    }
    stats.EndCard();
    stats.ShowView(detailView);
}

void ResetMap(MapStats@ m)
{
    m.seconds = 0;
    m.played = 0;
    m.restarts = m.respawns = m.falls = m.fallsAtStart = m.restartsAtStart = m.finishes = m.attempts = 0;
    m.checkpoints.resize(0);
    m.dirty = true;
    if (session.key == m.key)
        StartSession(m);                // this session starts again from nothing too
    Save();
    Log::Info("grind stats: reset " + m.key);
}

void OpenStats(bool open)
{
    stats.visible = open;
    if (open)
        BuildList();
}

void UpdateStats()
{
    if (footer.Clicked())
        OpenStats(!stats.visible);
    if (!stats.visible)
        return;
    if (closeButton.Clicked() || Input::Pressed(Input::Escape))
    {
        OpenStats(false);
        return;
    }
    for (uint i = 0; i < sortButtons.length(); i++)
        if (sortButtons[i].Clicked() && int(i) != sortMode)
        {
            sortMode = int(i);
            ShowSort();
            BuildList();
            return;
        }
    if (detailed is null)
    {
        for (uint i = 0; i < detailButtons.length(); i++)
            if (detailButtons[i].Clicked())
            {
                BuildDetail(listed[i]);
                return;
            }
        return;
    }
    if (backButton.Clicked())
    {
        BuildList();
        return;
    }
    if (resetButton.Clicked())
    {
        if (Host::Time() < resetArmedUntil)
        {
            ResetMap(detailed);
            BuildDetail(detailed);
        }
        else
        {
            resetArmedUntil = Host::Time() + 3;
            resetButton.label = "click again to reset";
        }
    }
    else if (resetArmedUntil > 0 && Host::Time() >= resetArmedUntil)
    {
        resetArmedUntil = 0;
        resetButton.label = "reset this map";
    }
}

// --- every frame ------------------------------------------------------------------------------------------------------

void Update(float dt)
{
    double now = Host::Time();
    double step = now - lastTick;
    if (step > 1.0)
        step = 1.0;                     // a hitch or a long load never adds more than a second
    lastTick = now;
    FollowSession();
    FollowInput();
    Count(step);
    UpdateCard();
    UpdateStats();
    if (now - lastSave > SAVE_EVERY)
        Save();
}
