// editor_test.mm  (macOS only)
// Loads the built plugin, opens its panel in an offscreen window the way a host
// does, renders screenshots, drives the controls with synthetic mouse events,
// checks host automation messages, and closes it again.
//
//   editor_test <plugin binary> <output dir for PNGs>

#import <Cocoa/Cocoa.h>

#include "../Source/VST2/vst2_abi.h"
#include "../Source/VST2/Params.h"
#include "../Source/VST2/Editor.h"

#include <dlfcn.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <algorithm>
#include <vector>

static int failures = 0;
static void check (bool ok, const char* what)
{
    std::printf ("  %s  %s\n", ok ? "ok  " : "FAIL", what);
    if (! ok) ++failures;
}

static int automateCalls = 0, beginCalls = 0, endCalls = 0;
static VstIntPtr VST_CALL hostCallback (AEffect*, VstInt32 opcode, VstInt32, VstIntPtr, void*, float)
{
    switch (opcode)
    {
        case audioMasterVersion:   return 2400;
        case audioMasterAutomate:  ++automateCalls; return 0;
        case audioMasterBeginEdit: ++beginCalls; return 1;
        case audioMasterEndEdit:   ++endCalls; return 1;
        default:                   return 0;
    }
}

typedef AEffect* (*EntryProc) (audioMasterCallback);

static VstIntPtr call (AEffect* e, VstInt32 op, VstInt32 idx = 0, VstIntPtr val = 0, void* ptr = 0, float opt = 0.0f)
{
    return e->dispatcher (e, op, idx, val, ptr, opt);
}

static NSData* renderPNG (NSView* v, const std::string& path)
{
    const NSRect b = [v bounds];
    NSBitmapImageRep* rep = [v bitmapImageRepForCachingDisplayInRect: b];
    [v cacheDisplayInRect: b toBitmapImageRep: rep];
    NSData* png = [rep representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]];
    [png writeToFile: [NSString stringWithUTF8String: path.c_str()] atomically: YES];
    std::printf ("  wrote %s (%lu bytes)\n", path.c_str(), (unsigned long) [png length]);
    return png;
}

// Send a mouse event at a point in the panel's (flipped) coordinates.
static void mouse (NSWindow* w, NSView* v, NSEventType type, NSPoint panelPt, int clicks = 1)
{
    const NSPoint wp = [v convertPoint: panelPt toView: nil];
    NSEvent* e = [NSEvent mouseEventWithType: type location: wp modifierFlags: 0 timestamp: 0
                                windowNumber: [w windowNumber] context: nil eventNumber: 0
                                  clickCount: clicks pressure: 1.0f];
    if (type == NSLeftMouseDown) [v mouseDown: e];
    else if (type == NSLeftMouseDragged) [v mouseDragged: e];
    else [v mouseUp: e];
}

static void pump (double secs)
{
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: secs]];
}

// Does the preset file hold this name line?
static bool fileHasLine (const std::string& path, const char* needle)
{
    bool found = false;
    FILE* nf = std::fopen (path.c_str(), "r");
    if (nf)
    {
        char ln[256];
        while (std::fgets (ln, sizeof (ln), nf)) if (std::strstr (ln, needle)) found = true;
        std::fclose (nf);
    }
    return found;
}

int main (int argc, char** argv)
{
    if (argc < 3) { std::printf ("usage: %s <plugin binary> <png dir>\n", argv[0]); return 2; }
    setvbuf (stdout, 0, _IONBF, 0);   // unbuffered, so a crash still shows how far it got
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    const std::string dir = argv[2];

    // Keep the test's presets away from any real ones
    const std::string presetFile = dir + "/test_presets/Presets.txt";
    setenv ("TBTYPEA_PRESET_FILE", presetFile.c_str(), 1);
    std::remove (presetFile.c_str());

    void* lib = dlopen (argv[1], RTLD_NOW | RTLD_LOCAL);
    if (! lib) { std::printf ("dlopen failed: %s\n", dlerror()); return 1; }
    EntryProc entry = (EntryProc) dlsym (lib, "VSTPluginMain");
    if (! entry) { std::printf ("no entry point\n"); return 1; }
    AEffect* e = entry (hostCallback);
    call (e, effOpen);
    call (e, effSetSampleRate, 0, 0, 0, 44100.0f);
    call (e, effMainsChanged, 0, 1);

    using namespace tbtypea;
    std::printf ("Editor\n");
    check ((e->flags & effFlagsHasEditor) != 0, "plugin reports a custom editor");
    ERect* r = 0;
    call (e, effEditGetRect, 0, 0, &r);
    check (r && r->right - r->left == kEditorWidth && r->bottom - r->top == kEditorHeight,
           "editor size as declared");

    NSWindow* win = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, kEditorWidth, kEditorHeight)
                                                styleMask: NSBorderlessWindowMask
                                                  backing: NSBackingStoreBuffered defer: NO];
    NSView* parent = [win contentView];
    check (call (e, effEditOpen, 0, 0, parent) == 1, "effEditOpen succeeds");
    check ([[parent subviews] count] == 1, "panel view added to the host's view");
    NSView* panel = [[parent subviews] count] ? [[parent subviews] objectAtIndex: 0] : nil;
    if (! panel) return 1;
    check (NSEqualSizes ([panel frame].size, NSMakeSize (kEditorWidth, kEditorHeight)), "panel has the declared size");

    NSData* pngDefault = renderPNG (panel, dir + "/panel_default.png");
    check ([pngDefault length] > 10000, "panel renders");

    std::printf ("\nControls\n");

    // Drag the BAND 2 level knob down 50 px: -0.25
    e->setParameter (e, kB2Level, 0.5f);
    const float g0 = e->getParameter (e, kB2Level);
    automateCalls = beginCalls = endCalls = 0;
    mouse (win, panel, NSLeftMouseDown,    NSMakePoint (760, 88));
    mouse (win, panel, NSLeftMouseDragged, NSMakePoint (760, 113));
    mouse (win, panel, NSLeftMouseDragged, NSMakePoint (760, 138));
    mouse (win, panel, NSLeftMouseUp,      NSMakePoint (760, 138));
    const float g1 = e->getParameter (e, kB2Level);
    std::printf ("  BAND 2 level %.2f -> %.2f\n", g0, g1);
    check (std::fabs (g1 - (g0 - 0.25f)) < 0.02f, "dragging a knob down turns it down");
    check (automateCalls > 0 && beginCalls == 1 && endCalls == 1, "host gets begin / automate / end");
    mouse (win, panel, NSLeftMouseDown, NSMakePoint (760, 88), 2);
    mouse (win, panel, NSLeftMouseUp,   NSMakePoint (760, 88), 2);
    check (std::fabs (e->getParameter (e, kB2Level) - kDefaults[kB2Level]) < 1e-6f, "double-click resets a knob");

    // Each knob answers where it is drawn (dragged up from mid-travel)
    {
        const int knobs[7] = { kStress, kB1Level, kB2Level, kB3Level, kB4Level, kInput, kOutput };
        const CGFloat kx[7] = { 500, 610, 760, 910, 1060, 1270, 1270 };
        const CGFloat ky[7] = { 88, 88, 88, 88, 88, 54, 116 };
        bool all = true;
        for (int k = 0; k < 7; ++k)
        {
            e->setParameter (e, knobs[k], 0.5f);
            mouse (win, panel, NSLeftMouseDown,    NSMakePoint (kx[k], ky[k]));
            mouse (win, panel, NSLeftMouseDragged, NSMakePoint (kx[k], ky[k] - 20));
            mouse (win, panel, NSLeftMouseUp,      NSMakePoint (kx[k], ky[k] - 20));
            if (! (e->getParameter (e, knobs[k]) > 0.55f)) { all = false; std::printf ("  knob %d did not turn\n", knobs[k]); }
            e->setParameter (e, knobs[k], kDefaults[knobs[k]]);
        }
        check (all, "all seven knobs and trimpots turn");
    }

    // Band on/off lamp buttons: each press toggles
    {
        const int sw[4] = { kB1On, kB2On, kB3On, kB4On };
        const CGFloat sx[4] = { 680, 830, 980, 1130 };
        bool all = true;
        for (int k = 0; k < 4; ++k)
        {
            mouse (win, panel, NSLeftMouseDown, NSMakePoint (sx[k], 88));
            mouse (win, panel, NSLeftMouseUp,   NSMakePoint (sx[k], 88));
            if (e->getParameter (e, sw[k]) >= 0.5f) all = false;
        }
        check (all, "BAND 1-4 buttons switch their bands off");
        // Leave bands 1 and 2 off for the screenshot (the Dolby A trick: bands 3 and 4)
        for (int k = 2; k < 4; ++k)
        {
            mouse (win, panel, NSLeftMouseDown, NSMakePoint (sx[k], 88));
            mouse (win, panel, NSLeftMouseUp,   NSMakePoint (sx[k], 88));
        }
        check (e->getParameter (e, kB3On) >= 0.5f && e->getParameter (e, kB4On) >= 0.5f, "and back on");
        pump (0.1);
        renderPNG (panel, dir + "/panel_bands_3_4.png");
        for (int k = 0; k < 2; ++k)
        {
            mouse (win, panel, NSLeftMouseDown, NSMakePoint (sx[k], 88));
            mouse (win, panel, NSLeftMouseUp,   NSMakePoint (sx[k], 88));
        }
    }

    // NR in-out (the on/off); rec is a lamp only
    mouse (win, panel, NSLeftMouseDown, NSMakePoint (345, 106));
    mouse (win, panel, NSLeftMouseUp,   NSMakePoint (345, 106));
    check (e->getParameter (e, kNr) < 0.5f, "NR button switches NR out");
    pump (0.1);
    renderPNG (panel, dir + "/panel_nr_out.png");
    mouse (win, panel, NSLeftMouseDown, NSMakePoint (345, 106));
    mouse (win, panel, NSLeftMouseUp,   NSMakePoint (345, 106));
    check (e->getParameter (e, kNr) >= 0.5f, "and NR back in");
    {
        float before[kNumParams];
        for (int i = 0; i < kNumParams; ++i) before[i] = e->getParameter (e, i);
        mouse (win, panel, NSLeftMouseDown, NSMakePoint (415, 106));
        mouse (win, panel, NSLeftMouseUp,   NSMakePoint (415, 106));
        bool same = true;
        for (int i = 0; i < kNumParams; ++i) if (e->getParameter (e, i) != before[i]) same = false;
        check (same, "the rec lamp is always lit and changes nothing");
    }
    mouse (win, panel, NSLeftMouseDown, NSMakePoint (190, 45));
    mouse (win, panel, NSLeftMouseUp,   NSMakePoint (190, 45));
    check (e->getParameter (e, kTone) >= 0.5f, "Dolby tone button switches the tone on");
    {
        const int n = 22050;
        std::vector<float> a (n, 0.0f), b (n, 0.0f), oa (n), ob (n);
        float* in[2] = { &a[0], &b[0] };
        float* out[2] = { &oa[0], &ob[0] };
        e->processReplacing (e, in, out, n);
        e->processReplacing (e, in, out, n);
        pump (0.3);
        renderPNG (panel, dir + "/panel_tone.png");
    }
    mouse (win, panel, NSLeftMouseDown, NSMakePoint (190, 45));
    mouse (win, panel, NSLeftMouseUp,   NSMakePoint (190, 45));
    check (e->getParameter (e, kTone) < 0.5f, "and off");

    // A knob turned shows in the readout
    mouse (win, panel, NSLeftMouseDown,    NSMakePoint (910, 88));
    mouse (win, panel, NSLeftMouseDragged, NSMakePoint (910, 128));
    mouse (win, panel, NSLeftMouseUp,      NSMakePoint (910, 128));
    renderPNG (panel, dir + "/panel_readout.png");
    e->setParameter (e, kB3Level, kDefaults[kB3Level]);

    std::printf ("\nPresets\n");
    #define SLOT(k) NSMakePoint (84.0 + (k) * 33.0 + 14.5, 214.0)
    e->setParameter (e, kB4Level, 0.3f);
    e->setParameter (e, kB1On, 0.0f);
    pump (0.1);
    mouse (win, panel, NSLeftMouseDown, NSMakePoint (53, 214));     // SAVE
    mouse (win, panel, NSLeftMouseUp,   NSMakePoint (53, 214));
    mouse (win, panel, NSLeftMouseDown, SLOT (2));                   // slot 3
    mouse (win, panel, NSLeftMouseUp,   SLOT (2));
    FILE* pf = std::fopen (presetFile.c_str(), "r");
    check (pf != 0, "SAVE then a slot writes the preset file");
    if (pf) std::fclose (pf);

    // Saving opens a name box over the readout
    NSTextField* field = nil;
    for (NSView* sv in [panel subviews]) if ([sv isKindOfClass: [NSTextField class]]) field = (NSTextField*) sv;
    check (field != nil, "saving opens a box to name the preset");
    renderPNG (panel, dir + "/panel_naming.png");
    if (field)
    {
        [field setStringValue: @"A forty character preset name for tests"];   // 40 characters
        [(id) panel controlTextDidChange: nil];
        renderPNG (panel, dir + "/panel_naming_long.png");
        [field setStringValue: @"Big slow flange"];
        [field sendAction: [field action] to: [field target]];       // Return
        pump (0.2);
    }
    check (fileHasLine (presetFile, "name 3: Big slow flange"), "Return saves the name with the preset");
    bool gone = true;
    for (NSView* sv in [panel subviews]) if ([sv isKindOfClass: [NSTextField class]]) gone = false;
    check (gone, "and the name box goes away");
    renderPNG (panel, dir + "/panel_preset_saved.png");
    e->setParameter (e, kB4Level, 0.9f);
    e->setParameter (e, kB1On, 1.0f);
    pump (0.1);
    automateCalls = 0;
    mouse (win, panel, NSLeftMouseDown, SLOT (2));
    mouse (win, panel, NSLeftMouseUp,   SLOT (2));
    check (std::fabs (e->getParameter (e, kB4Level) - 0.3f) < 1e-5f
           && e->getParameter (e, kB1On) < 0.5f, "clicking the slot recalls the saved settings");
    check (automateCalls >= kNumParams, "recall tells the host about every parameter");
    renderPNG (panel, dir + "/panel_preset_loaded.png");

    // Clicking the readout while the preset is in use renames it; Esc keeps the old name
    mouse (win, panel, NSLeftMouseDown, NSMakePoint (700, 215));
    mouse (win, panel, NSLeftMouseUp,   NSMakePoint (700, 215));
    field = nil;
    for (NSView* sv in [panel subviews]) if ([sv isKindOfClass: [NSTextField class]]) field = (NSTextField*) sv;
    check (field != nil && [[field stringValue] isEqualToString: @"Big slow flange"], "clicking the readout opens the name to edit");
    if (field)
    {
        [field setStringValue: @"Something else"];
        [(id) panel control: field textView: nil doCommandBySelector: @selector (cancelOperation:)];   // Esc
        pump (0.2);
    }
    check (fileHasLine (presetFile, "name 3: Big slow flange"), "Esc keeps the old name");
    const float before = e->getParameter (e, kB4Level);
    mouse (win, panel, NSLeftMouseDown, SLOT (5));                   // empty slot 6
    mouse (win, panel, NSLeftMouseUp,   SLOT (5));
    check (e->getParameter (e, kB4Level) == before, "an empty slot changes nothing");
    for (int i = 0; i < kNumParams; ++i) e->setParameter (e, i, kDefaults[i]);

    std::printf ("\nHost automation shows on the panel\n");
    pump (0.2);
    NSData* pngBefore = renderPNG (panel, dir + "/panel_before_host.png");
    e->setParameter (e, kB2Level, 0.2f);
    e->setParameter (e, kNr, 0.0f);
    pump (0.3);
    NSData* pngAfter = renderPNG (panel, dir + "/panel_changed.png");
    check (! [pngAfter isEqualToData: pngBefore], "panel redraws after host changes");
    e->setParameter (e, kB2Level, kDefaults[kB2Level]);
    e->setParameter (e, kNr, 1.0f);

    std::printf ("\nMeter follows the circuit\n");
    {
        const int n = 44100;
        std::vector<float> z (n, 0.0f), zz (n, 0.0f), oa (n), ob (n);
        float* zin[2] = { &z[0], &zz[0] };
        float* out[2] = { &oa[0], &ob[0] };
        e->processReplacing (e, zin, out, n);
        pump (0.3);
        NSData* quiet = renderPNG (panel, dir + "/panel_meter_rest.png");
        std::vector<float> a (n), b (n);
        for (int i = 0; i < n; ++i) a[i] = b[i] = (float) (0.17803 * std::sin (2.0 * 3.14159265358979 * 1000.0 * i / 44100.0));   // Dolby level
        float* in[2] = { &a[0], &b[0] };
        e->processReplacing (e, in, out, n);
        e->setParameter (e, kB1On, 0.0f);       // the vocal stresser: bands 3 and 4, STRESS up
        e->setParameter (e, kB2On, 0.0f);
        e->setParameter (e, kStress, 0.75f);
        mouse (win, panel, NSLeftMouseDown, NSMakePoint (1130, 88));     // readout shows BAND 4
        mouse (win, panel, NSLeftMouseUp,   NSMakePoint (1130, 88));
        mouse (win, panel, NSLeftMouseDown, NSMakePoint (1130, 88));
        mouse (win, panel, NSLeftMouseUp,   NSMakePoint (1130, 88));
        pump (0.3);
        NSData* lit = renderPNG (panel, dir + "/panel_showcase.png");
        check (! [lit isEqualToData: quiet], "meter needle moves to Dolby level while playing");
    }

    std::printf ("\nClose\n");
    call (e, effEditClose);
    check ([[parent subviews] count] == 0, "effEditClose removes the panel");
    check (call (e, effEditOpen, 0, 0, parent) == 1 && [[parent subviews] count] == 1, "reopens");
    call (e, effEditClose);
    call (e, effMainsChanged, 0, 0);
    call (e, effClose);
    [win release];
    [pool release];      // drain before unloading the plugin's code
    dlclose (lib);

    std::printf ("\n%s (%d failure%s)\n", failures ? "FAILED" : "ALL EDITOR CHECKS PASSED", failures, failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
