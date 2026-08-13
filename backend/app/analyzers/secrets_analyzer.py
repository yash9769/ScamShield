import re
import os
import logging
from typing import Dict, Any, List

logger = logging.getLogger(__name__)

class SecretsAnalyzer:
    def __init__(self):
        # Regex patterns for common secrets
        self.patterns = {
            "aws_access_key": re.compile(r"(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}"),
            "aws_secret_key": re.compile(r"(?i)aws_secret_access_key.{0,20}[=:].{0,5}([a-zA-Z0-9/+=]{40})"),
            "google_api_key": re.compile(r"AIza[0-9A-Za-z\\-_]{35}"),
            "firebase_url": re.compile(r"https://[a-z0-9-]+\.firebaseio\.com"),
            "jwt_token": re.compile(r"ey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
            "stripe_standard_api": re.compile(r"sk_live_[0-9a-zA-Z]{24}"),
            "supabase_url": re.compile(r"https://[a-z0-9-]+\.supabase\.co"),
            "openai_api_key": re.compile(r"sk-[a-zA-Z0-9]{48}"),
            "anthropic_api_key": re.compile(r"sk-ant-[a-zA-Z0-9]{40,}"),
            "github_token": re.compile(r"(ghp|gho|ghu|ghs|ghr)_[a-zA-Z0-9]{36}"),
            "private_key": re.compile(r"-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----"),
        }

    def analyze(self, directory: str) -> Dict[str, Any]:
        logger.info(f"Running Secrets Analyzer on {directory}")
        findings = {k: [] for k in self.patterns.keys()}
        total_found = 0
        
        if not os.path.exists(directory):
            return {"status": "error", "error": "Directory does not exist"}

        for root, _, files in os.walk(directory):
            for file in files:
                # Only scan likely text files (java, xml, strings, etc.)
                if file.endswith((".java", ".xml", ".txt", ".json", ".smali", ".yaml", ".yml", ".properties")):
                    file_path = os.path.join(root, file)
                    try:
                        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                            
                            for key, pattern in self.patterns.items():
                                matches = pattern.findall(content)
                                if matches:
                                    # Handle cases where findall returns tuples or strings
                                    for match in matches:
                                        match_str = match if isinstance(match, str) else match[0]
                                        findings[key].append({
                                            "file": file_path,
                                            "match": match_str[:10] + "..." if len(match_str) > 15 else match_str
                                        })
                                    total_found += len(matches)
                    except Exception as e:
                        logger.warning(f"Failed to read {file_path} for secrets: {e}")

        # Remove empty findings
        findings = {k: v for k, v in findings.items() if v}
        
        return {
            "status": "success",
            "findings": findings,
            "total_found": total_found
        }
