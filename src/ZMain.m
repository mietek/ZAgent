#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>

#import "ZCommon.h"
#import "ZCocoa.h"
#import "ZMain.h"


int main(int argc, char **argv) {
	(void)argc, (void)argv;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *app = [NSApplication sharedApplication];
	if (!ZAmIAuthorized()) {
		NSRunCriticalAlertPanel(@"Zug cannot run.", @"Please enable access for assistive devices in the Universal Access system preference pane.", @"OK", @"", @"");
		return EXIT_FAILURE;
	}
	ZKeyEventState state;
	state.action = Z_NO_ACTION;
	state.screenIndex = Z_NO_INDEX;
	state.anchor = Z_NO_ANCHOR;
	memset(&state.anchorCount, 0, sizeof(state.anchorCount));
	ZInstallKeyEventHandler(&ZHandleKeyEvent, &state);
	[app setDelegate: (id)[[[ZMain alloc] init] autorelease]];
	[app run];
	[pool release];
	return EXIT_SUCCESS;
}


@implementation ZMain

@synthesize statusItem;

- (void)applicationDidFinishLaunching: (NSNotification *)aNotification {
	(void)aNotification;
	NSMenu *menu = [[[NSMenu allocWithZone: [NSMenu menuZone]] init] autorelease];
	SEL terminate = NSSelectorFromString(@"terminate:");
	[menu addItemWithTitle: @"Quit" action: terminate keyEquivalent: @""];
	[self setStatusItem:[[NSStatusBar systemStatusBar] statusItemWithLength: NSSquareStatusItemLength]];
	[[self statusItem] setTitle: @"Z"];
	[[self statusItem] setMenu: menu];
	[[self statusItem] setHighlightMode: YES];
}

@end


void ZDoAction(ZAction action, ZIndex screenIndex, ZAnchor anchor, UInt32 anchorCount[Z_ANCHOR_COUNT]) {
	(void)action;
	// debugf("action: %d, anchorCount: %d, %d %d %d %d, %d %d %d %d, screenIndex: %d", action, anchorCount[Z_CENTER], anchorCount[Z_LEFT], anchorCount[Z_RIGHT], anchorCount[Z_TOP], anchorCount[Z_BOTTOM], anchorCount[Z_TOP_LEFT], anchorCount[Z_TOP_RIGHT], anchorCount[Z_BOTTOM_LEFT], anchorCount[Z_BOTTOM_RIGHT], screenIndex);
	AXUIElementRef win;
	if (!(win = ZCopyFrontApplicationFrontWindow()))
		return;
	CGRect srcWinBounds = ZGetWindowBounds(win);
	NSScreen *srcScreen;
	if (!(srcScreen = [NSScreen screenWithRect: ZFlipRect(srcWinBounds)]))
		halt("Error in ZHandleHotKey(): [NSScreen screenWithRect:] -> nil");
	CGRect srcScreenBounds = ZFlipRect([srcScreen visibleFrame]);
	NSScreen *dstScreen;
	if (!(dstScreen = [NSScreen screenWithIndex: screenIndex]))
		dstScreen = srcScreen;
	CGRect dstScreenBounds = ZFlipRect([dstScreen visibleFrame]);
	CGSize dstWinSize;
	CGRect dstWinBounds;
	if (anchor != Z_NO_ANCHOR) {
		CGRect dstBaseBounds;
		UInt32 dstBaseParts = anchorCount[Z_CENTER] + 1;
		if (dstBaseParts <= 2) // Ugh, seems irregular
			dstBaseBounds = dstScreenBounds;
		else {
			CGFloat dstBaseWidthRatio = 2.0 / dstBaseParts;
			CGSize dstBaseSize = CGSizeMake(round(dstScreenBounds.size.width * dstBaseWidthRatio), dstScreenBounds.size.height);
			dstBaseBounds = ZAnchorRect(Z_CENTER, dstBaseSize, dstScreenBounds);
		}
		UInt32 dstWinWidthParts = anchorCount[Z_LEFT] + anchorCount[Z_RIGHT] + anchorCount[Z_TOP_LEFT] + anchorCount[Z_TOP_RIGHT] + anchorCount[Z_BOTTOM_LEFT] + anchorCount[Z_BOTTOM_RIGHT] + 1;
		if (dstWinWidthParts <= 1)
			dstWinSize.width = dstBaseBounds.size.width;
		else {
			CGFloat dstWinWidthRatio = 1.0 / dstWinWidthParts;
			dstWinSize.width = round(dstBaseBounds.size.width * dstWinWidthRatio);
		}
		UInt32 dstWinHeightParts = anchorCount[Z_TOP] + anchorCount[Z_BOTTOM] + anchorCount[Z_TOP_LEFT] + anchorCount[Z_TOP_RIGHT] + anchorCount[Z_BOTTOM_LEFT] + anchorCount[Z_BOTTOM_RIGHT] + 1;
		if (dstWinHeightParts <= 1)
			dstWinSize.height = dstBaseBounds.size.height;
		else {
			CGFloat dstWinHeightRatio = 1.0 / dstWinHeightParts;
			dstWinSize.height = round(dstBaseBounds.size.height * dstWinHeightRatio);
		}
		UInt32 dstWinHorizPart = 0;
		if (anchor == Z_LEFT || anchor == Z_TOP_LEFT || anchor == Z_BOTTOM_LEFT)
			dstWinHorizPart = anchorCount[Z_RIGHT] + anchorCount[Z_TOP_RIGHT] + anchorCount[Z_BOTTOM_RIGHT];
		else if (anchor == Z_RIGHT || anchor == Z_TOP_RIGHT || anchor == Z_BOTTOM_RIGHT)
			dstWinHorizPart = anchorCount[Z_LEFT] + anchorCount[Z_TOP_LEFT] + anchorCount[Z_BOTTOM_LEFT];
		UInt32 dstWinVertPart = 0;
		if (anchor == Z_TOP || anchor == Z_TOP_LEFT || anchor == Z_TOP_RIGHT)
			dstWinVertPart = anchorCount[Z_BOTTOM] + anchorCount[Z_BOTTOM_LEFT] + anchorCount[Z_BOTTOM_RIGHT];
		else if (anchor == Z_BOTTOM || anchor == Z_BOTTOM_LEFT || anchor == Z_BOTTOM_RIGHT)
			dstWinVertPart = anchorCount[Z_TOP] + anchorCount[Z_TOP_LEFT] + anchorCount[Z_TOP_RIGHT];
		dstWinBounds = ZAnchorPartRect(anchor, dstWinSize, dstWinHorizPart, dstWinVertPart, dstBaseBounds);
	}
	else {
		if (srcScreen == dstScreen)
			return;
		anchor = ZGuessAnchor(srcWinBounds, srcScreenBounds); // TODO: This should return Z_NO_ANCHOR and we should handle this by origin ratios
		CGSize ratio = ZGuessRatio(srcWinBounds, srcScreenBounds);
		dstWinSize = CGSizeMake(round(dstScreenBounds.size.width * ratio.width), round(dstScreenBounds.size.height * ratio.height));
		dstWinBounds = ZAnchorRect(anchor, dstWinSize, dstScreenBounds);
	}
	ZSetWindowSize(win, dstWinBounds.size);
	ZSetWindowOrigin(win, dstWinBounds.origin);
	ZSetWindowSize(win, dstWinBounds.size); // Ugh, maybe use CGSPrivate instead
}

Boolean ZHandleKeyEvent(CGEventRef event, void *handlerData) {
	ZKeyEventState *state = (ZKeyEventState *)handlerData;
	ZAction action = ZFlagsToAction(CGEventGetFlags(event));
	CGEventType type = CGEventGetType(event);
	if (type == kCGEventKeyDown) {
		if (state->action == Z_NO_ACTION) {
			if (action != Z_NO_ACTION) {
				int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
				ZIndex screenIndex = ZKeycodeToIndex(keycode);
				if (screenIndex != Z_NO_INDEX) {
					if ([NSScreen screenWithIndex: screenIndex]) {
						state->action = action;
						state->screenIndex = screenIndex;
						ZDoAction(state->action, state->screenIndex, state->anchor, state->anchorCount);
					}
					else
						NSBeep();
					return true;
				}
				ZAnchor anchor = ZKeycodeToAnchor(keycode);
				if (anchor != Z_NO_ANCHOR) {
					state->action = action;
					state->anchor = anchor;
					state->anchorCount[anchor]++;
					ZDoAction(state->action, state->screenIndex, state->anchor, state->anchorCount);
					return true;
				}
			}
		}
		else {
			if (action != Z_NO_ACTION) {
				int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
				ZIndex screenIndex = ZKeycodeToIndex(keycode);
				if (screenIndex != Z_NO_INDEX) {
					if ([NSScreen screenWithIndex: screenIndex]) {
						state->screenIndex = screenIndex;
						ZDoAction(state->action, state->screenIndex, state->anchor, state->anchorCount);
					}
					else
						NSBeep();
					return true;
				}
				ZAnchor anchor = ZKeycodeToAnchor(keycode);
				if (anchor != Z_NO_ANCHOR) {
					if (state->anchor == Z_NO_ANCHOR || state->anchor == Z_CENTER) // Ugh, maybe use a separate field
						state->anchor = anchor;
					state->anchorCount[anchor]++;
					ZDoAction(state->action, state->screenIndex, state->anchor, state->anchorCount);
					return true;
				}
			}
		}
	}
	else if (type == kCGEventFlagsChanged) {
		if (state->action != Z_NO_ACTION && action == Z_NO_ACTION) {
			state->action = Z_NO_ACTION;
			state->anchor = Z_NO_ANCHOR;
			memset(state->anchorCount, 0, sizeof(state->anchorCount));
			state->screenIndex = Z_NO_INDEX;
			return true;
		}
	}
	return false;
}


ZAnchor ZKeycodeToAnchor(int64_t keycode) {
	if (ZIsKeycodeCenter(keycode))
		return Z_CENTER;
	if (ZIsKeycodeLeft(keycode))
		return Z_LEFT;
	if (ZIsKeycodeRight(keycode))
		return Z_RIGHT;
	if (ZIsKeycodeTop(keycode))
		return Z_TOP;
	if (ZIsKeycodeBottom(keycode))
		return Z_BOTTOM;
	if (ZIsKeycodeTopLeft(keycode))
		return Z_TOP_LEFT;
	if (ZIsKeycodeTopRight(keycode))
		return Z_TOP_RIGHT;
	if (ZIsKeycodeBottomLeft(keycode))
		return Z_BOTTOM_LEFT;
	if (ZIsKeycodeBottomRight(keycode))
		return Z_BOTTOM_RIGHT;
	return Z_NO_ANCHOR;
}

Boolean ZIsKeycodeCenter(int64_t keycode) {
	return keycode == kVK_ANSI_S;
}

Boolean ZIsKeycodeLeft(int64_t keycode) {
	return keycode == kVK_ANSI_A;
}

Boolean ZIsKeycodeRight(int64_t keycode) {
	return keycode == kVK_ANSI_D;
}

Boolean ZIsKeycodeTop(int64_t keycode) {
	return keycode == kVK_ANSI_W;
}

Boolean ZIsKeycodeBottom(int64_t keycode) {
	return keycode == kVK_ANSI_X;
}

Boolean ZIsKeycodeTopLeft(int64_t keycode) {
	return keycode == kVK_ANSI_Q;
}

Boolean ZIsKeycodeTopRight(int64_t keycode) {
	return keycode == kVK_ANSI_E;
}

Boolean ZIsKeycodeBottomLeft(int64_t keycode) {
	return keycode == kVK_ANSI_Z;
}

Boolean ZIsKeycodeBottomRight(int64_t keycode) {
	return keycode == kVK_ANSI_C;
}

ZIndex ZKeycodeToIndex(int64_t keycode) {
	if (ZIsKeycode1(keycode))
		return Z_INDEX_1;
	if (ZIsKeycode2(keycode))
		return Z_INDEX_2;
	if (ZIsKeycode3(keycode))
		return Z_INDEX_3;
	if (ZIsKeycode4(keycode))
		return Z_INDEX_4;
	if (ZIsKeycode5(keycode))
		return Z_INDEX_5;
	if (ZIsKeycode6(keycode))
		return Z_INDEX_6;
	if (ZIsKeycode7(keycode))
		return Z_INDEX_7;
	if (ZIsKeycode8(keycode))
		return Z_INDEX_8;
	if (ZIsKeycode9(keycode))
		return Z_INDEX_9;
	return Z_NO_INDEX;
}

Boolean ZIsKeycode1(int64_t keycode) {
	return keycode == kVK_ANSI_1;
}

Boolean ZIsKeycode2(int64_t keycode) {
	return keycode == kVK_ANSI_2;
}

Boolean ZIsKeycode3(int64_t keycode) {
	return keycode == kVK_ANSI_3;
}

Boolean ZIsKeycode4(int64_t keycode) {
	return keycode == kVK_ANSI_4;
}

Boolean ZIsKeycode5(int64_t keycode) {
	return keycode == kVK_ANSI_5;
}

Boolean ZIsKeycode6(int64_t keycode) {
	return keycode == kVK_ANSI_6;
}

Boolean ZIsKeycode7(int64_t keycode) {
	return keycode == kVK_ANSI_7;
}

Boolean ZIsKeycode8(int64_t keycode) {
	return keycode == kVK_ANSI_8;
}

Boolean ZIsKeycode9(int64_t keycode) {
	return keycode == kVK_ANSI_9;
}

ZAction ZFlagsToAction(CGEventFlags flags) {
	if (ZAreFlagsFocus(flags))
		return Z_FOCUS_ACTION;
	if (ZAreFlagsResize(flags))
		return Z_RESIZE_ACTION;
	if (ZAreFlagsMove(flags))
		return Z_MOVE_ACTION;
	return Z_NO_ACTION;
}

Boolean ZAreFlagsFocus(CGEventFlags flags) {
	return flags & kCGEventFlagMaskSecondaryFn && !(flags & kCGEventFlagMaskControl) && !(flags & kCGEventFlagMaskShift);
}

Boolean ZAreFlagsResize(CGEventFlags flags) {
	return flags & kCGEventFlagMaskSecondaryFn && flags & kCGEventFlagMaskControl && !(flags & kCGEventFlagMaskShift);
}

Boolean ZAreFlagsMove(CGEventFlags flags) {
	return flags & kCGEventFlagMaskSecondaryFn && !(flags & kCGEventFlagMaskControl) && flags & kCGEventFlagMaskShift;
}
