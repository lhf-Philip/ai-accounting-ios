package org.duckdns.lhfser.aiaccounting

import android.app.Application
import org.duckdns.lhfser.aiaccounting.data.AppContainer

class AIAccountingApp : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}
