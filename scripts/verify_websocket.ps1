$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$uri = New-Object System.Uri("ws://127.0.0.1:8000/ws")

try {
    Write-Host "Connecting to $uri..."
    $ws.ConnectAsync($uri, $cts.Token).Wait()

    if ($ws.State -eq 'Open') {
        Write-Host "Socket State: Open"
        
        $message = "Hello from PowerShell"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
        # Use explicit constructor for ArraySegment
        $segment = New-Object "System.ArraySegment[byte]" -ArgumentList @(,$buffer)
        
        Write-Host "Sending: $message"
        $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
        
        $rcvBuffer = New-Object byte[] 1024
        # Use explicit constructor for ArraySegment
        $rcvSegment = New-Object "System.ArraySegment[byte]" -ArgumentList @(,$rcvBuffer)
        
        Write-Host "Waiting for response..."
        $task = $ws.ReceiveAsync($rcvSegment, $cts.Token)
        $task.Wait()
        $result = $task.Result
        
        $received = [System.Text.Encoding]::UTF8.GetString($rcvBuffer, 0, $result.Count)
        Write-Host "Received: $received"
        
        if ($received -match $message) {
            Write-Host "VERIFICATION SUCCESS: Echo received"
        } else {
            Write-Host "VERIFICATION FAILED: Unexpected response"
        }

        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Done", $cts.Token).Wait()
    } else {
        Write-Host "Failed to open connection. State: $($ws.State)"
        exit 1
    }
} catch {
    Write-Error "Exception: $_"
    exit 1
}
