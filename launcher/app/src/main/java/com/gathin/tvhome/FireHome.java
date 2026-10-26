package com.gathin.tvhome;

import android.accessibilityservice.AccessibilityService;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

/**
 * stock_home_fast: the fast path for stock_home_redirect on Fire OS, where Amazon's launcher is a protected package
 * that can be neither disabled nor replaced as Home.
 *
 * After the remote's Home, Fire OS (Android 9) holds back every activity start that an app makes for about five
 * seconds (APP_SWITCH_DELAY_TIME), so HomeKeyService's ordinary startActivity left Amazon's home on screen for that
 * long. Here the launch is an activity PendingIntent fired by AlarmManager: system_server starts it, and its starts
 * are exempt from that hold. The alarm can only fire at once with
 * {@code settings put global alarm_manager_constants min_futurity=0}, which the Fire OS install script sets.
 *
 * While the switch happens a black accessibility overlay covers Amazon's home. An accessibility service may draw
 * that window type with no overlay permission. The cover takes no keys or touches and is always lifted on a timer.
 *
 * Fail-open: if this launcher does not come up (it crashed, it was uninstalled), the redirects stop after a few
 * tries and Amazon's home is left alone for a while, so the TV can never be stuck on a black screen or a loop.
 */
final class FireHome {

    private static final String TAG = "FireHome";

    /** One Home press can bring Amazon's home up with more than one window event; right after this launcher has
     *  landed, a late duplicate is ignored (a person cannot press Home twice that fast on purpose). */
    static final long DUPLICATE_MS = 250L;
    /** The cover stays until MainActivity has drawn (HomeKeyService.launcherShown), and never longer than this. It is
     *  also how long a launch counts as in flight. */
    static final long COVER_MAX_MS = 2_500L;
    /** Settings.Global key that picks how the alarm is set, to measure them on a TV without a rebuild:
     *  "exact" (default, setExact), "idle" (setExactAndAllowWhileIdle) or "clock" (setAlarmClock).
     *  Measured on an AFTTIFF43 (Fire OS 7.7.1.7), Home to this launcher drawn, three runs each: exact 0.57-0.61 s
     *  and clock 0.53-0.62 s, with the launch in the same millisecond as the alarm; idle 0.49-2.8 s, because Android
     *  rations allow-while-idle alarms set in quick succession and held the launch back by up to 2.9 s. */
    static final String ALARM_MODE_KEY = "cyt_fire_alarm";
    /** Launches that never land, each started within LOOP_GAP_MS of the one before: more than LOOP_LIMIT of them in a
     *  row means this launcher cannot come up, and Amazon's home is then left alone for BACK_OFF_MS. A launch that
     *  lands resets the count, so pressing Home quickly and often never trips it. */
    static final long LOOP_GAP_MS = 4_000L;
    static final int LOOP_LIMIT = 4;
    static final long BACK_OFF_MS = 30_000L;

    private static final int REQUEST_CODE = 0xF1E;

    private final AccessibilityService service;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable timeout = this::timedOut;
    private View cover;

    private long lastRedirect = -LOOP_GAP_MS;
    private long lastLanded = -DUPLICATE_MS;
    /** Until when a launch is on its way; Amazon's home coming up meanwhile is noted, not launched again at once. */
    private long inFlightUntil;
    private boolean amazonAgain;
    /** Launches in a row that did not land. */
    private int streak;
    private long backOffUntil;

    FireHome(AccessibilityService service) {
        this.service = service;
    }

    /** Amazon's home screen came to the front. */
    void redirect() {
        long now = SystemClock.uptimeMillis();
        if (now < inFlightUntil) {
            // A launch is on its way. If it lands, this launcher is on top and all is well; if Amazon's home came up
            // over it instead, the launch never lands and timedOut sends Home here again.
            amazonAgain = true;
            return;
        }
        if (!shouldRedirect(now, backOffUntil, inFlightUntil, lastLanded)) return;
        streak = nextStreak(streak, now, lastRedirect);
        if (streak > LOOP_LIMIT) {
            Log.w(TAG, "this launcher did not come up after " + LOOP_LIMIT + " tries; leaving Amazon's home alone");
            backOffUntil = now + BACK_OFF_MS;
            streak = 0;
            return;
        }
        lastRedirect = now;
        amazonAgain = false;
        inFlightUntil = now + COVER_MAX_MS;
        Log.i(TAG, "redirect: Amazon home in front, unanswered " + streak);
        showCover();
        handler.removeCallbacks(timeout);
        handler.postDelayed(timeout, COVER_MAX_MS);
        if (!launchFromAlarm()) {
            // No alarm: an ordinary start still lands, after Fire OS's hold.
            try {
                service.startActivity(homeIntent(service));
            } catch (RuntimeException e) {
                Log.w(TAG, "could not start the launcher", e);
                handler.removeCallbacks(timeout);
                hideCover();
                inFlightUntil = 0;
            }
        }
    }

    /** This launcher's home screen has drawn: the switch is done. */
    void landed() {
        if (cover != null) Log.i(TAG, "landed: launcher in front, cover lifted");
        handler.removeCallbacks(timeout);
        lastLanded = SystemClock.uptimeMillis();
        inFlightUntil = 0;
        amazonAgain = false;
        streak = 0;
        hideCover();
    }

    /** The launch did not land within COVER_MAX_MS. */
    private void timedOut() {
        hideCover();
        inFlightUntil = 0;
        if (amazonAgain) {
            amazonAgain = false;
            Log.i(TAG, "Amazon home came back during the launch; again");
            redirect();
        }
    }

    void release() {
        handler.removeCallbacksAndMessages(null);
        hideCover();
    }

    static boolean shouldRedirect(long now, long backOffUntil, long inFlightUntil, long lastLanded) {
        return now >= backOffUntil && now >= inFlightUntil && now - lastLanded >= DUPLICATE_MS;
    }

    static int nextStreak(int streak, long now, long lastRedirect) {
        return now - lastRedirect < LOOP_GAP_MS ? streak + 1 : 1;
    }

    static Intent homeIntent(Context context) {
        return new Intent(context, MainActivity.class)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                        | Intent.FLAG_ACTIVITY_NO_ANIMATION);
    }

    /** An activity PendingIntent, not a broadcast: a broadcast would start the activity from this app's own uid,
     *  which is exactly what Fire OS holds back. */
    private boolean launchFromAlarm() {
        try {
            AlarmManager alarms = service.getSystemService(AlarmManager.class);
            if (alarms == null) return false;
            PendingIntent launch = PendingIntent.getActivity(service, REQUEST_CODE, homeIntent(service),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            String mode = Settings.Global.getString(service.getContentResolver(), ALARM_MODE_KEY);
            long now = System.currentTimeMillis();
            if ("clock".equals(mode)) {
                alarms.setAlarmClock(new AlarmManager.AlarmClockInfo(now, launch), launch);
            } else if ("idle".equals(mode)) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, now, launch);
            } else {
                mode = "exact";
                alarms.setExact(AlarmManager.RTC_WAKEUP, now, launch);
            }
            Log.i(TAG, "alarm set: " + mode);
            return true;
        } catch (RuntimeException e) {
            Log.w(TAG, "alarm launch failed", e);
            return false;
        }
    }

    private void showCover() {
        if (cover != null) return;
        WindowManager windows = service.getSystemService(WindowManager.class);
        if (windows == null) return;
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.OPAQUE);
        lp.gravity = Gravity.TOP | Gravity.START;
        View v = new View(service);
        v.setBackgroundColor(Color.BLACK);
        try {
            windows.addView(v, lp);
            cover = v;
            Log.i(TAG, "cover up");
        } catch (RuntimeException e) {
            Log.w(TAG, "cover unavailable; the switch will show", e);
        }
    }

    private void hideCover() {
        if (cover == null) return;
        try {
            service.getSystemService(WindowManager.class).removeView(cover);
        } catch (RuntimeException ignored) {
            // already gone
        }
        cover = null;
        Log.i(TAG, "cover down");
    }
}
