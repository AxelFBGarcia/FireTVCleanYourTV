package com.gathin.tvhome;

import org.junit.Test;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FireHomeTest {
    private static final long LONG_AGO = -FireHome.DUPLICATE_MS;

    @Test public void theFirstHomeRedirects() {
        assertTrue(FireHome.shouldRedirect(10_000, 0, 0, LONG_AGO));
    }

    @Test public void notWhileALaunchIsOnItsWay() {
        assertFalse(FireHome.shouldRedirect(10_000, 0, 11_000, LONG_AGO));
        assertTrue(FireHome.shouldRedirect(11_000, 0, 11_000, LONG_AGO));
    }

    @Test public void aQuickSecondPressAfterLandingRedirects() {
        // Landed at 10 000, Home again 400 ms later: that is a person, not a duplicate event.
        assertTrue(FireHome.shouldRedirect(10_400, 0, 0, 10_000));
    }

    @Test public void aLateDuplicateRightAfterLandingDoesNot() {
        assertFalse(FireHome.shouldRedirect(10_100, 0, 0, 10_000));
    }

    @Test public void nothingRedirectsWhileBackingOff() {
        assertFalse(FireHome.shouldRedirect(20_000, 50_000, 0, LONG_AGO));
        assertTrue(FireHome.shouldRedirect(50_000, 50_000, 0, LONG_AGO));
    }

    @Test public void launchesInQuickSuccessionCount() {
        assertEquals(2, FireHome.nextStreak(1, 11_000, 10_000));
    }

    @Test public void aLaunchLongAfterTheLastStartsOver() {
        assertEquals(1, FireHome.nextStreak(3, 10_000 + FireHome.LOOP_GAP_MS, 10_000));
    }
}
