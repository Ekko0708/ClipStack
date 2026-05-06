#include "cs_hotkey.h"
#include <Carbon/Carbon.h>
#include <dispatch/dispatch.h>

static EventHandlerRef sHandlerRef = NULL;
static EventHotKeyRef sHotKeyRef = NULL;
static EventHandlerUPP sUPP = NULL;
static CSHotkeyHandler sCallback = NULL;

static OSStatus csHotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    (void)nextHandler;
    (void)theEvent;
    (void)userData;
    if (sCallback != NULL) {
        CSHotkeyHandler cb = sCallback;
        dispatch_async(dispatch_get_main_queue(), ^{
            cb();
        });
    }
    return noErr;
}

void cs_hotkey_unregister(void) {
    if (sHotKeyRef != NULL) {
        UnregisterEventHotKey(sHotKeyRef);
        sHotKeyRef = NULL;
    }
    if (sHandlerRef != NULL) {
        RemoveEventHandler(sHandlerRef);
        sHandlerRef = NULL;
    }
    sCallback = NULL;
}

int cs_hotkey_register(uint32_t modifiers, CSHotkeyHandler handler) {
    cs_hotkey_unregister();
    sCallback = handler;

    if (sUPP == NULL) {
        sUPP = NewEventHandlerUPP(csHotKeyHandler);
        if (sUPP == NULL) {
            return 0;
        }
    }

    EventTypeSpec spec;
    spec.eventClass = kEventClassKeyboard;
    spec.eventKind = kEventHotKeyPressed;

    OSStatus st = InstallEventHandler(GetApplicationEventTarget(), sUPP, 1, &spec, NULL, &sHandlerRef);
    if (st != noErr) {
        cs_hotkey_unregister();
        return 0;
    }

    EventHotKeyID hkid;
    hkid.signature = (OSType) 'CSHK';
    hkid.id = 1;

    st = RegisterEventHotKey((UInt32)kVK_Space, modifiers, hkid, GetApplicationEventTarget(), 0, &sHotKeyRef);
    if (st != noErr) {
        cs_hotkey_unregister();
        return 0;
    }
    return 1;
}
