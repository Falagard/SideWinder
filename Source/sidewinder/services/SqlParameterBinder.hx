package sidewinder.services;

/**
 * Named-parameter binding for SQLite (`@name` placeholders), used by
 * `SqliteDatabaseService.buildSqlStatic` and therefore by every `IDatabaseService` call that passes
 * a params map. Dependency-free (no `core.IServerConfig`, no native sqlite) so the core test suite
 * can cover it - see tests/sidewinder/services/SqlParameterBinderTest.hx.
 *
 * The previous implementation ran one `StringTools.replace(sql, "@" + key, value)` per
 * parameter (longest key first) over the whole statement - including text already
 * substituted for earlier keys. A value containing `@` followed by another parameter's name
 * was rewritten mid-literal: `["email" => "x@id.example.com", "id" => "42"]` produced
 * `'x'42'.example.com'` - broken SQL, and for crafted values (`"@role, admin = 1 --"` next to an
 * `@role` parameter) SQL injection. It also
 * matched `@id` inside a longer, unbound placeholder such as `@idea`.
 *
 * Now, mirroring `Database.buildSql` / `MySqlDatabaseService.buildSql`:
 *  - substituted values are emitted once and never rescanned;
 *  - a placeholder is `@` + a full identifier ([A-Za-z0-9_]+); unknown names are left as-is;
 *  - text inside single-quoted SQL literals (with '' escapes) is copied untouched.
 * Value formatting is unchanged (see `formatSqlLiteral`).
 */
class SqlParameterBinder {
    public static function bind(sql:String, params:Map<String, Dynamic>):String {
        if (params == null || !params.keys().hasNext()) return sql;
        var out = new StringBuf();
        var n = sql.length;
        var i = 0;
        // Unchanged text is copied in runs with addSub, never addChar: HL strings are UTF-16 and
        // fastCodeAt yields code units, so a per-char copy would split surrogate pairs (emoji).
        var runStart = 0;
        while (i < n) {
            var code = StringTools.fastCodeAt(sql, i);
            if (code == "'".code) {
                // Skip over the whole quoted literal (it stays part of the run), honouring '' escapes.
                i++;
                while (i < n) {
                    if (StringTools.fastCodeAt(sql, i) == "'".code) {
                        if (i + 1 < n && StringTools.fastCodeAt(sql, i + 1) == "'".code) {
                            i += 2;
                            continue;
                        }
                        i++;
                        break;
                    }
                    i++;
                }
                continue;
            }
            if (code == "@".code) {
                var j = i + 1;
                while (j < n && isSqlIdentChar(StringTools.fastCodeAt(sql, j))) j++;
                if (j > i + 1) {
                    var name = sql.substr(i + 1, j - i - 1);
                    if (params.exists(name)) {
                        out.addSub(sql, runStart, i - runStart);
                        out.add(formatSqlLiteral(params.get(name)));
                        i = j;
                        runStart = j;
                        continue;
                    }
                }
            }
            i++;
        }
        out.addSub(sql, runStart, n - runStart);
        return out.toString();
    }

    static inline function isSqlIdentChar(c:Int):Bool {
        return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code)
            || (c >= "0".code && c <= "9".code) || c == "_".code;
    }

    /** SQL literal for a bound value. Formatting rules are unchanged from the original binder. */
    public static function formatSqlLiteral(val:Dynamic):String {
        var escapedVal:String;
        if (val == null) {
            escapedVal = "NULL";
        } else if (Std.isOfType(val, String)) {
            escapedVal = "'" + StringTools.replace(Std.string(val), "'", "''") + "'";
        } else if (Std.isOfType(val, Bool)) {
            escapedVal = val ? "1" : "0";
        } else if (Std.isOfType(val, Date)) {
            var time = val.getTime() / 1000.0;
            escapedVal = Std.string(time);
        } else if (Std.isOfType(val, sidewinder.interfaces.IDatabaseService.RawSql)) {
            escapedVal = cast(val, sidewinder.interfaces.IDatabaseService.RawSql).value;
        } else if (Std.isOfType(val, Float)) {
            var s = Std.string(val);
            if (s.indexOf("e") != -1 || s.indexOf("E") != -1) {
                // Manual formatting for large floats (timestamps) to avoid scientific notation
                escapedVal = haxe.format.JsonPrinter.print(val);
            } else {
                escapedVal = s;
            }
        } else {
            escapedVal = Std.string(val);
        }
        return escapedVal == null ? "NULL" : escapedVal;
    }
}
