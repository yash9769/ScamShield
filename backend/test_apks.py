import os
import sys
import httpx
import asyncio
import time
from rich.console import Console
from rich.table import Table

console = Console()

APK_DIR = os.getenv("SCAMSHIELD_TEST_APK_DIR", os.path.join(os.path.dirname(__file__), "test_apks"))
BASE_URL = os.getenv("SCAMSHIELD_BASE_URL", "http://localhost:8000")

APKS_TO_TEST = [
    "1_benign_debug.apk",
    "2_permissions_debug.apk",
    "3_network_debug.apk",
    "4_secrets_debug.apk",
    "5_native_debug.apk",
    "6_large_debug.apk"
]

async def check_health():
    console.print("[cyan]Waiting for backend to become healthy...[/cyan]")
    async with httpx.AsyncClient() as client:
        for i in range(30):
            try:
                resp = await client.get(f"{BASE_URL}/health")
                if resp.status_code == 200:
                    console.print("[green]Backend is healthy![/green]")
                    return True
            except Exception as e:
                pass
            await asyncio.sleep(5)
            console.print(f"Still waiting for backend... ({i+1}/30)")
    console.print("[red]Backend failed to become healthy in time.[/red]")
    return False

async def scan_apk(apk_name: str) -> dict:
    apk_path = os.path.join(APK_DIR, apk_name)
    if not os.path.exists(apk_path):
        console.print(f"[red]File not found: {apk_path}[/red]")
        return {"status": "File not found"}

    console.print(f"[cyan]Scanning {apk_name}...[/cyan]")
    start = time.time()
    
    async with httpx.AsyncClient(timeout=300.0) as client:
        with open(apk_path, "rb") as f:
            files = {'file': (apk_name, f, 'application/vnd.android.package-archive')}
            data = {'force_reanalyze': 'true'}
            try:
                response = await client.post(f"{BASE_URL}/scan", files=files, data=data)
                duration = time.time() - start
                if response.status_code == 200:
                    console.print(f"[green]Successfully scanned {apk_name} in {duration:.1f}s[/green]")
                    return response.json()
                else:
                    console.print(f"[red]Failed to scan {apk_name}: {response.text}[/red]")
                    return {"status": f"HTTP {response.status_code}"}
            except Exception as e:
                console.print(f"[red]Error scanning {apk_name}: {e}[/red]")
                return {"status": f"Error: {str(e)}"}

async def run_tests():
    if not await check_health():
        return

    results = []
    for apk in APKS_TO_TEST:
        result = await scan_apk(apk)
        # Store results
        if result.get("status") == "completed":
            risk = result.get("risk", {}).get("level", "UNKNOWN")
            score = result.get("risk", {}).get("score", 0)
            results.append((apk, "Completed", f"{risk} ({score})", "Pass"))
        else:
            status = result.get("status", "Failed")
            results.append((apk, "Completed", status, "Fail"))
            
    # Print Table
    table = Table(title="ScamShield QA Results")
    table.add_column("APK", style="cyan")
    table.add_column("Expected", style="magenta")
    table.add_column("Actual", style="yellow")
    table.add_column("Pass/Fail", style="green")

    for row in results:
        color = "green" if row[3] == "Pass" else "red"
        table.add_row(row[0], row[1], row[2], f"[{color}]{row[3]}[/{color}]")

    console.print(table)

if __name__ == "__main__":
    asyncio.run(run_tests())
