package sidewinder.services;

import sidewinder.interfaces.IDatabaseService.RawSql;
import utest.Assert;
import utest.Test;

/**
 * `@name` parameter binding behind every SqliteDatabaseService call that passes a params map.
 *
 * The original binder ran one global `StringTools.replace` per key over the whole statement,
 * so text substituted for one key was rescanned for the next. These tests pin the single-pass
 * behaviour. Against the old implementation the first test fails with
 * `VALUES ('x42.example.com', 42)` and the injection test with `display_name = ''viewer', admin = 1 --'`.
 */
class SqlParameterBinderTest extends Test {
	function testValueContainingAnotherPlaceholderIsNotRewritten() {
		Assert.equals("INSERT INTO t (email, id) VALUES ('x@id.example.com', 42)",
			SqlParameterBinder.bind("INSERT INTO t (email, id) VALUES (@email, @id)", ["email" => "x@id.example.com", "id" => 42]));
	}

	function testInjectionAttemptThroughAtSignStaysOneLiteral() {
		// The old binder substituted the longer key first, then replaced the @role INSIDE that
		// value with a quoted literal - closing the string early so the rest ran as SQL:
		//   SET display_name = ''viewer', admin = 1 --', role = 'viewer' ...
		var sql = SqlParameterBinder.bind("UPDATE users SET display_name = @display_name, role = @role WHERE id = @id",
			["display_name" => "@role, admin = 1 --", "role" => "viewer", "id" => 7]);
		Assert.equals("UPDATE users SET display_name = '@role, admin = 1 --', role = 'viewer' WHERE id = 7", sql);
	}

	function testPlaceholderMatchesWholeIdentifierOnly() {
		Assert.equals("SELECT 1 WHERE a = 'x' AND b = @idea", SqlParameterBinder.bind("SELECT 1 WHERE a = @id AND b = @idea", ["id" => "x"]));
		Assert.equals("SELECT 'x', 'y'", SqlParameterBinder.bind("SELECT @id, @idea", ["id" => "x", "idea" => "y"]));
		Assert.equals("SELECT 'y', 'x'", SqlParameterBinder.bind("SELECT @idea, @id", ["id" => "x", "idea" => "y"]));
	}

	function testSamePlaceholderUsedTwice() {
		Assert.equals("UPDATE t SET a = 5, b = 5", SqlParameterBinder.bind("UPDATE t SET a = @now, b = @now", ["now" => 5]));
	}

	function testQuotedSqlLiteralsAreLeftAlone() {
		Assert.equals("SELECT '@id', 'it''s @id', 3", SqlParameterBinder.bind("SELECT '@id', 'it''s @id', @id", ["id" => 3]));
	}

	function testUnknownPlaceholdersAndBareAtSignsAreUntouched() {
		Assert.equals("SELECT @missing, @, 1", SqlParameterBinder.bind("SELECT @missing, @, @x", ["x" => 1]));
	}

	function testValueFormattingIsUnchanged() {
		Assert.equals("NULL", SqlParameterBinder.bind("@v", ["v" => null]));
		Assert.equals("'O''Brien'", SqlParameterBinder.bind("@v", ["v" => "O'Brien"]));
		Assert.equals("1 0", SqlParameterBinder.bind("@t @f", ["t" => true, "f" => false]));
		Assert.equals("42 2.5", SqlParameterBinder.bind("@i @f", ["i" => 42, "f" => 2.5]));
		Assert.equals("1790000000000", SqlParameterBinder.bind("@ms", ["ms" => 1790000000000.0]), "large floats avoid scientific notation");
		Assert.equals("CURRENT_TIMESTAMP", SqlParameterBinder.bind("@r", ["r" => new RawSql("CURRENT_TIMESTAMP")]));
		Assert.equals("SELECT 1", SqlParameterBinder.bind("SELECT 1", null));
		Assert.equals("SELECT 1", SqlParameterBinder.bind("SELECT 1", new Map()));
	}

	function testNonAsciiTextAndValuesSurvive() {
		Assert.equals("SELECT '🎸 Café' AS t, 'naïve 🎵'", SqlParameterBinder.bind("SELECT '🎸 Café' AS t, @v", ["v" => "naïve 🎵"]));
		Assert.equals("-- 🎸 note\nSELECT 1", SqlParameterBinder.bind("-- 🎸 note\nSELECT @x", ["x" => 1]));
	}
}
