# SideWinder Development Workflow

Internal guide for AI agents and developers to build, test, and manage the SideWinder application.

## Build Process

### HashLink (Primary Target)
To rebuild the application for the HashLink target:
```bash
lime build hl
```
**Important**: If the build fails with an error like `Cannot copy to "Export/hl/bin/lime.hdll", is the file in use?`, it means the server is still running. See the **Cleanup** section.

## Testing Process

### Unit Tests
To run the automated tests:
```bash
lix lime test hl
```
**Database Location**: After running tests, the SQLite database used by the test suite is located at:
`export/hl/bin/data.db`
*Note: Ensure the database is not locked by another process during tests if they perform DB operations.*

## Running the Application

### Server Startup (Windows)
The executable is located in `export\hl\bin\SideWinder.exe`. The production/run database is also located in this directory:
`export\hl\bin\data.db`
```powershell
cd export\hl\bin; $p = Start-Process .\SideWinder.exe -PassThru -NoNewWindow; Start-Sleep -s 5; $p.Id
```
*Tip: Always wait a few seconds after starting to ensure the server is fully initialized before sending requests.*

### Logging
The server outputs logs to `stdout` and potentially a log file depends on configuration. To capture output for debugging:
```powershell
.\SideWinder.exe > output.txt 2>&1
```

## Cleanup and Process Management

### Stopping the Server
On Windows, use `taskkill` to force-stop the server if it's hanging or locking files:
```powershell
taskkill /fi "imagename eq SideWinder.exe" /f
```
**CRITICAL**: Always run this before building if you suspects the server is running. You can check if it's running first:
```powershell
tasklist /fi "imagename eq SideWinder.exe"
```

## Common Issues & Troubleshooting
1. **File Locks**: `lime.hdll` or `SideWinder.exe` being locked is the most common build failure. Always `taskkill` first.
## Testing with curl or Postman

Once the server is running, you can verify authentication using the `X-API-KEY` header.

### Using curl
Run the following command in your terminal:
```bash
curl -v -H "X-API-KEY: sk_test_6789" http://localhost:8001/api/me
```

### Using Postman
1.  **Method**: Set to `GET` (or the appropriate method for your endpoint).
2.  **URL**: `http://localhost:8001/api/me`
3.  **Headers**:
    - Add a new key: `X-API-KEY`
    - Value: `your_api_key_here` (e.g., `sk_test_6789`)
4.  **Send**: Click the "Send" button.

**Expected Response**:
- **Status**: `200 OK`
- **Body**: A JSON object containing user information and session details.
```json
{
  "userId": 911,
  "provider": "api_key",
  "token": "sk_test_6789"
}
```
