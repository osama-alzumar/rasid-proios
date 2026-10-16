package pro.rasid.core

data class SyncReport(val sent: Int = 0, val rejected: Int = 0, val membersUpdated: Int = 0, val offline: Boolean = false)

/**
 * Pushes the outbox, then pulls what changed on the server.
 *
 * The outbox is flushed first and the pull is skipped if any send failed
 * transiently: otherwise a send whose response was lost would be counted twice
 * (in the pulled server balance and as still pending) until the retry comes
 * back as already_applied.
 */
class SyncEngine(private val store: LocalStore, private val api: ApiClient) {

    suspend fun sync(includeTransactions: Boolean = true): SyncReport {
        var sent = 0
        var rejected = 0
        for (op in store.pendingOperations) {
            try {
                store.confirm(op.id, api.createTransaction(op.draft, op.id))
                sent++
            } catch (e: ApiError) {
                when {
                    e.isTransient -> { store.noteAttempt(op.id, e.message); return SyncReport(sent, rejected, offline = true) }
                    e is ApiError.Rejected -> { store.markRejected(op.id, e.message); rejected++ }
                    // Session-level (expired token / shop / disabled): keep the queue, let the app react.
                    else -> throw e
                }
            }
        }
        return try {
            // Only a super admin can have a selected shop; the role itself is read
            // from the bootstrap response, not from the cached snapshot.
            val shopId = store.snapshot.selectedShopId
            store.applyBootstrap(api.bootstrap(shopId))
            val isSuperAdmin = store.snapshot.user?.isSuperAdmin == true
            var updated = 0
            if (!isSuperAdmin || shopId != null) {
                updated = pullMembers(shopId)
                if (includeTransactions) store.setRecentTransactions(api.recentTransactions(shopId = shopId))
            }
            SyncReport(sent, rejected, updated)
        } catch (e: ApiError) {
            if (e.isTransient) SyncReport(sent, rejected, offline = true) else throw e
        }
    }

    /** Downloads members changed since the last sync (everything the first time). */
    private suspend fun pullMembers(shopId: Int?): Int {
        val since = store.snapshot.membersSyncedAt
        var afterId = 0
        var updated = 0
        var serverTime: String? = null
        while (true) {
            val page = api.members(since, afterId, shopId)
            if (serverTime == null) serverTime = page.serverTime
            store.applyMembersPage(page)
            updated += page.members.size
            if (!page.hasMore || page.nextAfterId == null) break
            afterId = page.nextAfterId
        }
        // The first page's time is the next cursor, so changes made while later
        // pages were downloading are fetched again next time.
        serverTime?.let { store.finishMembersSync(it) }
        return updated
    }
}
