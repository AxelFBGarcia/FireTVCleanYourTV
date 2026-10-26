package com.gathin.tvhome;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;

/**
 * restore_key_services at boot. ServiceRepair runs when Home starts, but on Fire OS Amazon's home comes up at boot
 * and this launcher only follows if HomeKeyService is still on the enabled list. Fire OS can take it off (a force
 * stop, a low-memory kill, an update), so put it back here as well. Does nothing without restore_key_services or
 * without WRITE_SECURE_SETTINGS (ServiceRepair checks).
 */
public class BootRepair extends BroadcastReceiver {

    /** ServiceRepair writes the list from its own thread over about two seconds. */
    private static final long KEEP_ALIVE_MS = 3_000L;

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        if (!Config.load(context).restoreKeyServices) return;
        PendingResult pending = goAsync();
        ServiceRepair.restore(context);
        new Handler(Looper.getMainLooper()).postDelayed(pending::finish, KEEP_ALIVE_MS);
    }
}
