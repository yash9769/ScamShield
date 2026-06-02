// lib/data/cache/local_cache.dart

/// A simple in-memory LRU-style cache with optional TTL.
///
/// Used to avoid redundant SQLite reads on hot paths (e.g. history list).
class LocalCache<T> {
  final int _maxEntries;
  final Duration? _ttl;

  final Map<String, _CacheEntry<T>> _store = {};

  LocalCache({int maxEntries = 32, Duration? ttl})
      : _maxEntries = maxEntries,
        _ttl = ttl;

  /// Returns the cached value for [key], or null if missing / expired.
  T? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (_ttl != null &&
        DateTime.now().difference(entry.createdAt) > _ttl!) {
      _store.remove(key);
      return null;
    }
    return entry.value;
  }

  /// Stores [value] for [key].
  void set(String key, T value) {
    if (_store.length >= _maxEntries) {
      // Evict oldest entry
      final oldest = _store.entries
          .reduce((a, b) =>
              a.value.createdAt.isBefore(b.value.createdAt) ? a : b)
          .key;
      _store.remove(oldest);
    }
    _store[key] = _CacheEntry(value);
  }

  /// Removes a single [key] from the cache.
  void invalidate(String key) => _store.remove(key);

  /// Clears all cached entries.
  void clear() => _store.clear();

  /// Whether a non-expired entry for [key] exists.
  bool contains(String key) => get(key) != null;
}

class _CacheEntry<T> {
  final T value;
  final DateTime createdAt;

  _CacheEntry(this.value) : createdAt = DateTime.now();
}
