import Foundation

/// A tiny key/value cache backed by the `cache` table. Used to memoize
/// translation/definition lookups (provider-namespaced keys) so free quotas are
/// respected and results work offline afterwards.
struct CacheRepository {
    let db: Database

    func get(_ key: String) -> String? {
        (try? db.query("SELECT value FROM cache WHERE cache_key=?;", [key]) { $0.string(0) })?.first
    }

    func put(_ key: String, _ value: String) {
        _ = try? db.run("INSERT OR REPLACE INTO cache(cache_key, value, created_at) VALUES(?,?,?);",
                        [key, value, Date()])
    }
}
