package sidewinder.test;

import utest.Assert;
import utest.Test;
import sidewinder.services.UserService;
import sidewinder.services.AuthService;
import sidewinder.interfaces.ICacheService;
import sidewinder.services.InMemoryCacheService;
import sidewinder.core.DI;
import sidewinder.interfaces.IDatabaseService;
import sidewinder.services.SqliteDatabaseService;

class APIKeyTests extends Test {
    var userService:UserService;
    var authService:AuthService;
    var db:IDatabaseService;

    public function setup() {
        // Initialize DI and services
        db = new SqliteDatabaseService();
        DI.register(IDatabaseService, db);
        db.runMigrations();

        userService = new UserService();
        var cache = new InMemoryCacheService();
        authService = new AuthService(userService, cache);
    }

    public function testApiKeyAuthentication() {
        // 1. Create a test user
        var user = userService.create({
            id: 0,
            name: "Test Developer",
            email: "dev@example.com"
        });

        // 2. Insert an API key for the user using hashing and metadata
        var apiKey = "sk_test_6789";
        var hash = sidewinder.data.AuthUtils.hashApiKey(apiKey);
        var meta = sidewinder.data.AuthUtils.getApiKeyMetadata(apiKey);
        
        var query = "INSERT INTO user_api_keys (user_id, key_hash, prefix, last_four, name) VALUES " +
                    "(" + user.id + ", '" + hash + "', '" + meta.prefix + "', '" + meta.lastFour + "', 'Test Key')";
        db.execute(query);

        // 3. Authenticate with the API key
        var session = authService.authenticateWithApiKey(apiKey);

        // 4. Verify
        Assert.notNull(session);
        Assert.equals(user.id, session.userId);
        Assert.equals("api_key", session.provider);

        // 5. Verify DB content (negative test for plaintext)
        var rs = db.read("SELECT key_hash FROM user_api_keys WHERE user_id = " + user.id);
        Assert.isTrue(rs.hasNext());
        var row = rs.next();
        Assert.equals(hash, row.key_hash);
        Assert.notEquals(apiKey, row.key_hash);
    }

    public function testInvalidApiKey() {
        var caught = false;
        try {
            authService.authenticateWithApiKey("sk_bad_1234");
        } catch (e:Dynamic) {
            caught = true;
        }
        Assert.isTrue(caught);
    }

    public function testInactiveApiKey() {
        // 1. Create a test user
        var user = userService.create({
            id: 0,
            name: "Inactive Developer",
            email: "inactive@example.com"
        });

        // 2. Insert an inactive key with hash
        var apiKey = "sk_inactive_9999";
        var hash = sidewinder.data.AuthUtils.hashApiKey(apiKey);
        var meta = sidewinder.data.AuthUtils.getApiKeyMetadata(apiKey);

        var query = "INSERT INTO user_api_keys (user_id, key_hash, prefix, last_four, name, is_active) VALUES " +
                    "(" + user.id + ", '" + hash + "', '" + meta.prefix + "', '" + meta.lastFour + "', 'Inactive Key', 0)";
        db.execute(query);

        // 3. Attempt authentication
        var caught = false;
        try {
            authService.authenticateWithApiKey(apiKey);
        } catch (e:Dynamic) {
            caught = true;
        }
        Assert.isTrue(caught);
    }
}
