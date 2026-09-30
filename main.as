// Grind Stats: how long you've spent on every map, how often you restarted it, and where you get stuck.
//
// For each map (the game's own tracks and every workshop or local map), kept across launches:
//   time         all the time the map was on screen: racing, the pre-race menu and the pause menu too (not while
//                a replay is watched, and not in the track editor)
//   restarts     restarts from the beginning (Backspace, or R before the first checkpoint)
//   respawns     R at a checkpoint, counted for that checkpoint
//   falls        falls into the kill zone, counted for the checkpoint the ball goes back to (or the start)
//   finishes     runs finished
// Checkpoints are numbered in the order you first reached them and recognised by where they are, so a checkpoint keeps
// its number between sessions. Everything comes from the game (Race::Restarts, Respawns, Falls, CurrentCheckpoint),
// not from key presses, so rebinding keys changes nothing.
//
// A small box shows this map's numbers while you play (it can be dragged while the cursor is on screen). The
// "grind stats" footer button opens every map's stats with the totals; a map's "details" shows its checkpoints.

[Setting name="Show overlay" description="The small box with this map's numbers while you play"]
bool ShowOverlay = true;

[Setting name="Overlay size" min=12 max=48 description="Height of the overlay's text, in pixels"]
float OverlaySize = 18;

[Setting name="Background" min=0 max=1 description="How dark the box behind the overlay is (0: none)"]
float BackgroundOpacity = 0.35f;

// Colours (linear, as the widgets take them), the same as the ghost viewer's.
const float WINDOW_R = 0.0052f, WINDOW_G = 0.0060f, WINDOW_B = 0.0086f;     // #101217
const float CARD_R = 0.0116f, CARD_G = 0.0137f, CARD_B = 0.0194f;           // #1c1f26
const float BUTTON_R = 0.0232f, BUTTON_G = 0.0273f, BUTTON_B = 0.0382f;     // #2a2e37
const float PRIMARY_R = 0.0782f, PRIMARY_G = 0.2051f, PRIMARY_B = 0.0048f;  // #4f7d0f
const float MUTED_R = 0.2582f, MUTED_G = 0.2747f, MUTED_B = 0.3185f;        // #8b8f99
const float WARN_R = 0.8879f, WARN_G = 0.5333f, WARN_B = 0.0762f;           // #f2c14e
const float GREEN_R = 0.235f, GREEN_G = 1.0f, GREEN_B = 0.353f;             // the grind timer's green

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
    int finishes = 0;
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
bool wasComplete = false;
int seenCheckpoint = -1;
double lastTick = 0, lastSave = 0;

// --- the windows ------------------------------------------------------------------------------------------------------

UI::FooterButton@ footer;
UI::Window@ overlay;
UI::Text@ overlayName;
UI::Text@ overlayTime;
UI::Text@ overlayCounts;
UI::Text@ overlayCheckpoint;

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
    wasComplete = Race::IsComplete();
    lastTick = lastSave = Host::Time();

    @footer = UI::AddFooterButton("grind stats");
    BuildOverlay();
    BuildStats();
    Log::Info("grind stats: " + maps.length() + " map(s), " + TimeText(TotalSeconds()) + " in all");
}

// --- saving -----------------------------------------------------------------------------------------------------------
// Storage keeps one line per key: "maps" lists every map's key (joined by '|'), "m:<key>" a map's numbers and
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
                           "" + m.lastPlayed};
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
    current.lastPlayed = ++playCounter;
    current.custom = Race::IsCustomTrack();
    current.dirty = true;
    indexDirty = true;
    seenCheckpoint = -1;
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

void Count(double step)
{
    int restarts = Race::Restarts(), respawns = Race::Respawns(), falls = Race::Falls();
    bool complete = Race::IsComplete();
    if (Counting())
    {
        string key = Race::TrackKey();
        if (current is null || current.key != key)
            Enter(key);
        ReadTrack(current);
        current.seconds += step;
        current.dirty = true;
        int index = Race::CurrentCheckpoint();
        Checkpoint@ cp = index >= 0 ? Known(current, index) : null;
        if (restarts > seenRestarts)
            current.restarts += restarts - seenRestarts;
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
        if (complete && !wasComplete)
            current.finishes++;
        seenCheckpoint = index;
    }
    else if (current !is null)
    {
        @current = null;
        Save();
    }
    seenRestarts = restarts;
    seenRespawns = respawns;
    seenFalls = falls;
    wasComplete = complete;
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

// --- the overlay ------------------------------------------------------------------------------------------------------
//   Chaos2
//   0:42:17
//   restarts 36   respawns 120   falls 12   finishes 3
//   checkpoint 3: 14 respawns, 2 falls         (only on maps with checkpoints)

void BuildOverlay()
{
    @overlay = UI::CreateWindow();
    overlay.SetAnchor(0, 0);
    overlay.SetPivot(0, 0);
    overlay.SetOffset(40, 200);
    overlay.visible = false;
    @overlayName = Muted(overlay.AddText("", OverlaySize));
    overlay.NewRow();
    @overlayTime = overlay.AddText("0:00:00", OverlaySize * 1.8f);
    overlayTime.SetColor(GREEN_R, GREEN_G, GREEN_B, 1);
    overlay.NewRow();
    @overlayCounts = overlay.AddText("", OverlaySize);
    overlay.NewRow();
    @overlayCheckpoint = overlay.AddText("", OverlaySize);
    overlay.movable = true;             // after SetOffset: that is where "reset position" puts it back
    OnSettingsChanged();
}

// The plugin manager changed a setting.
void OnSettingsChanged()
{
    overlayName.size = OverlaySize;
    overlayTime.size = OverlaySize * 1.8f;
    overlayCounts.size = OverlaySize;
    overlayCheckpoint.size = OverlaySize;
    overlay.SetBackground(0, 0, 0, BackgroundOpacity);
}

void UpdateOverlay()
{
    overlay.visible = ShowOverlay && current !is null;
    if (!overlay.visible)
        return;
    overlayName.text = current.name;
    overlayTime.text = TimeText(current.seconds);
    overlayCounts.text = "restarts " + current.restarts + "   respawns " + current.respawns + "   falls " + current.falls +
                         "   finishes " + current.finishes;
    // The checkpoint line only on maps that have checkpoints.
    overlayCheckpoint.visible = current.checkpointTotal > 0;
    if (current.checkpointTotal == 0)
        return;
    if (seenCheckpoint < 0)
        overlayCheckpoint.text = "start: " + Plural(current.fallsAtStart, "fall");
    else
    {
        Checkpoint@ cp = Known(current, seenCheckpoint);
        overlayCheckpoint.text = cp is null ? "" : "checkpoint " + NumberOf(current, cp) + ": " + Plural(cp.respawns, "respawn") + ", " + Plural(cp.falls, "fall");
    }
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
        Muted(Column("-", 140));
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
    m.restarts = m.respawns = m.falls = m.fallsAtStart = m.finishes = 0;
    m.checkpoints.resize(0);
    m.dirty = true;
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
    Count(step);
    UpdateOverlay();
    UpdateStats();
    if (now - lastSave > SAVE_EVERY)
        Save();
}
