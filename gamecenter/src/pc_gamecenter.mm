#import <GameKit/GameKit.h>
#import <UIKit/UIKit.h>

#include "pc_gamecenter.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

void PCGameCenter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("authenticate"), &PCGameCenter::authenticate);
	ClassDB::bind_method(D_METHOD("fetch_proof"), &PCGameCenter::fetch_proof);
	ClassDB::bind_method(D_METHOD("is_authenticated"), &PCGameCenter::is_authenticated);
	ADD_SIGNAL(MethodInfo("authenticated", PropertyInfo(Variant::BOOL, "ok"), PropertyInfo(Variant::STRING, "player_id")));
	ADD_SIGNAL(MethodInfo("proof", PropertyInfo(Variant::DICTIONARY, "data")));
}

static String pc_str(NSString *s) {
	return s ? String::utf8(s.UTF8String) : String();
}

static UIViewController *pc_top_view_controller() {
	UIWindow *win = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) {
				win = w;
				break;
			}
		}
		if (!win && ((UIWindowScene *)scene).windows.count > 0) {
			win = ((UIWindowScene *)scene).windows.firstObject;
		}
		if (win) {
			break;
		}
	}
	UIViewController *vc = win.rootViewController;
	while (vc.presentedViewController) {
		vc = vc.presentedViewController;
	}
	return vc;
}

bool PCGameCenter::is_authenticated() const {
	return GKLocalPlayer.localPlayer.isAuthenticated;
}

void PCGameCenter::emit_authenticated(bool ok) {
	String pid = ok ? pc_str(GKLocalPlayer.localPlayer.teamPlayerID) : String();
	call_deferred("emit_signal", "authenticated", ok, pid);
}

void PCGameCenter::authenticate() {
	GKLocalPlayer *lp = GKLocalPlayer.localPlayer;
	if (lp.isAuthenticated) {
		emit_authenticated(true);
		return;
	}
	uint64_t id = get_instance_id();
	lp.authenticateHandler = ^(UIViewController *vc, NSError *error) {
		if (vc) {
			UIViewController *top = pc_top_view_controller();
			if (top) {
				[top presentViewController:vc animated:YES completion:nil];
			}
			return;
		}
		PCGameCenter *self_ = Object::cast_to<PCGameCenter>(ObjectDB::get_instance(id));
		if (self_) {
			self_->emit_authenticated(GKLocalPlayer.localPlayer.isAuthenticated);
		}
	};
}

void PCGameCenter::fetch_proof() {
	uint64_t id = get_instance_id();
	[GKLocalPlayer.localPlayer fetchItemsForIdentityVerificationSignature:^(NSURL *url, NSData *signature, NSData *salt,
			uint64_t timestamp, NSError *error) {
		Dictionary d;
		if (!error && url && signature && salt) {
			d["public_key_url"] = pc_str(url.absoluteString);
			d["signature"] = pc_str([signature base64EncodedStringWithOptions:0]);
			d["salt"] = pc_str([salt base64EncodedStringWithOptions:0]);
			d["timestamp"] = String::num_uint64(timestamp);
			d["player_id"] = pc_str(GKLocalPlayer.localPlayer.teamPlayerID);
			d["bundle_id"] = pc_str(NSBundle.mainBundle.bundleIdentifier);
		}
		Object *o = ObjectDB::get_instance(id);
		if (o) {
			o->call_deferred("emit_signal", "proof", d);
		}
	}];
}
