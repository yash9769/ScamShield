import os
import json
import logging
from typing import Dict, Any
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors

logger = logging.getLogger(__name__)

class ReportGenerator:
    def __init__(self, output_dir: str = "/app/reports"):
        self.output_dir = output_dir
        os.makedirs(self.output_dir, exist_ok=True)

    def generate_pdf(self, report_id: str, analysis_data: Dict[str, Any]) -> str:
        pdf_path = os.path.join(self.output_dir, f"{report_id}.pdf")
        
        try:
            doc = SimpleDocTemplate(pdf_path, pagesize=letter)
            styles = getSampleStyleSheet()
            elements = []

            # Title
            elements.append(Paragraph(f"ScamShield Analysis Report", styles['Title']))
            elements.append(Spacer(1, 12))

            # Summary
            elements.append(Paragraph("Executive Summary", styles['Heading1']))
            risk_info = analysis_data.get("risk", {})
            elements.append(Paragraph(f"<b>Risk Level:</b> {risk_info.get('level', 'UNKNOWN')}", styles['Normal']))
            elements.append(Paragraph(f"<b>Risk Score:</b> {risk_info.get('score', 0)}", styles['Normal']))
            
            ai_explanation = analysis_data.get("ai_explanation", "No AI explanation available.")
            elements.append(Spacer(1, 6))
            elements.append(Paragraph("<b>AI Analysis:</b>", styles['Normal']))
            elements.append(Paragraph(ai_explanation, styles['Normal']))
            elements.append(Spacer(1, 12))

            # Package Info & Hashes
            elements.append(Paragraph("Application Info", styles['Heading1']))
            andro_info = analysis_data.get("androguard", {})
            elements.append(Paragraph(f"<b>Package:</b> {andro_info.get('package', 'Unknown')}", styles['Normal']))
            elements.append(Paragraph(f"<b>Version:</b> {andro_info.get('version_name', 'Unknown')} ({andro_info.get('version_code', 'Unknown')})", styles['Normal']))
            elements.append(Paragraph(f"<b>SHA256:</b> {analysis_data.get('hash', 'Unknown')}", styles['Normal']))
            elements.append(Spacer(1, 12))
            
            # Permissions
            elements.append(Paragraph("Permissions", styles['Heading2']))
            permissions = andro_info.get("permissions", [])
            if permissions:
                for perm in permissions[:10]: # Limit to 10 for brevity in PDF
                    elements.append(Paragraph(f"- {perm}", styles['Normal']))
                if len(permissions) > 10:
                    elements.append(Paragraph(f"... and {len(permissions)-10} more", styles['Normal']))
            else:
                elements.append(Paragraph("No permissions found.", styles['Normal']))
            elements.append(Spacer(1, 12))

            # MobSF Findings
            elements.append(Paragraph("MobSF Findings", styles['Heading2']))
            mobsf_info = analysis_data.get("mobsf", {})
            mobsf_status = mobsf_info.get("status", "unknown")
            elements.append(Paragraph(f"Status: {mobsf_status}", styles['Normal']))
            if mobsf_status == "success":
                mobsf_score = mobsf_info.get("report", {}).get("security_score", "Unknown")
                elements.append(Paragraph(f"Security Score: {mobsf_score}", styles['Normal']))
            elements.append(Spacer(1, 12))

            # YARA Findings
            elements.append(Paragraph("YARA Findings", styles['Heading2']))
            yara_info = analysis_data.get("yara", {})
            yara_matches = yara_info.get("matches", [])
            if yara_matches:
                for match in yara_matches:
                    elements.append(Paragraph(f"- Rule matched: {match.get('rule')}", styles['Normal']))
            else:
                elements.append(Paragraph("No YARA rules matched.", styles['Normal']))
            elements.append(Spacer(1, 12))

            # OSINT Findings
            elements.append(Paragraph("OSINT (VirusTotal)", styles['Heading2']))
            osint_info = analysis_data.get("osint", {}).get("virustotal", {})
            if osint_info:
                elements.append(Paragraph(f"Malicious: {osint_info.get('malicious', 0)}", styles['Normal']))
                elements.append(Paragraph(f"Suspicious: {osint_info.get('suspicious', 0)}", styles['Normal']))
                elements.append(Paragraph(f"Undetected: {osint_info.get('undetected', 0)}", styles['Normal']))
            else:
                elements.append(Paragraph("No OSINT data available.", styles['Normal']))
            
            # Risk Details & Evidence Panel
            elements.append(Spacer(1, 12))
            elements.append(Paragraph("Evidence Panel", styles['Heading2']))
            
            if risk_info.get("details"):
                for detail in risk_info.get("details", []):
                    elements.append(Paragraph(f"- <b>Risk Factor:</b> {detail}", styles['Normal']))
            else:
                elements.append(Paragraph("No significant risk factors found.", styles['Normal']))
                
            # Additional Evidence Aggregation
            elements.append(Spacer(1, 6))
            if mobsf_status == "success":
                trackers_data = mobsf_info.get("report", {}).get("trackers")
                trackers_count = 0
                if isinstance(trackers_data, (dict, list)):
                    trackers_count = len(trackers_data)
                elif isinstance(trackers_data, int):
                    trackers_count = trackers_data
                elif isinstance(trackers_data, str) and trackers_data.isdigit():
                    trackers_count = int(trackers_data)
                
                if trackers_count > 0:
                    elements.append(Paragraph(f"- <b>Trackers Found:</b> {trackers_count}", styles['Normal']))
            
            secrets_info = analysis_data.get("secrets", {}).get("findings", {})
            if secrets_info:
                elements.append(Paragraph(f"- <b>Exposed Secrets Found:</b> {len(secrets_info)}", styles['Normal']))

            doc.build(elements)
            logger.info(f"PDF report generated at {pdf_path}")
            return pdf_path
            
        except Exception as e:
            logger.error(f"Failed to generate PDF report: {e}")
            return ""

    def save_json(self, report_id: str, analysis_data: Dict[str, Any]) -> str:
        json_path = os.path.join(self.output_dir, f"{report_id}.json")
        try:
            with open(json_path, 'w') as f:
                json.dump(analysis_data, f, indent=2)
            return json_path
        except Exception as e:
            logger.error(f"Failed to save JSON report: {e}")
            return ""
