package pro.rasid.app

import android.app.Application

class RasidApplication : Application() {
    /** Created by MainActivity on first launch (it knows whether demo mode was requested). */
    var model: AppModel? = null
}
