package com.kratosgym.kratos_gym_mobile

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable highest refresh rate available on the device
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            // For Android 11 (API 30) and above
            window.attributes.preferredDisplayModeId = getHighestRefreshRateMode()
        } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            // For Android 6.0 (API 23) to Android 10 (API 29)
            val params = window.attributes
            params.preferredRefreshRate = getHighestRefreshRate()
            window.attributes = params
        }
    }
    
    private fun getHighestRefreshRateMode(): Int {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            val display = windowManager.defaultDisplay
            val modes = display.supportedModes
            var maxRefreshRate = 60f
            var modeId = 0
            
            for (mode in modes) {
                if (mode.refreshRate > maxRefreshRate) {
                    maxRefreshRate = mode.refreshRate
                    modeId = mode.modeId
                }
            }
            
            return modeId
        }
        return 0
    }
    
    private fun getHighestRefreshRate(): Float {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            val display = windowManager.defaultDisplay
            val modes = display.supportedModes
            var maxRefreshRate = 60f
            
            for (mode in modes) {
                if (mode.refreshRate > maxRefreshRate) {
                    maxRefreshRate = mode.refreshRate
                }
            }
            
            return maxRefreshRate
        }
        return 60f
    }
}
