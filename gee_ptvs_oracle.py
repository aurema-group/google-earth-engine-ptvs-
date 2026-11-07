import hashlib
import json
from datetime import datetime
from typing import Optional
import ee
from pydantic import BaseModel, Field, validator

# Inicializar Google Earth Engine
try:
    ee.Initialize()
except Exception as e:
    print(f"⚠️ Error inicializando GEE (ejecuta 'earthengine authenticate' primero): {e}")

# 1. Esquema de Validación Institucional (Pydantic)
class GEEEvaluationReport(BaseModel):
    assetId: str = Field(..., description="Unique identifier of the RWA asset")
    evaluationEngine: str = Field("Google Earth Engine (Sentinel-1/2)", description="Source of telemetry")
    timestamp: str = Field(..., description="ISO 8601 UTC timestamp of evaluation")
    metrics: dict = Field(..., description="Telemetry metrics including structural integrity")

    @validator('timestamp')
    def timestamp_must_be_utc(cls, v):
        if not v.endswith('Z'):
            raise ValueError("Timestamp must be in UTC (ending with 'Z')")
        return v

class GEEPTVSOracle:
    def __init__(self, asset_id: str, coordinates: list):
        self.asset_id = asset_id
        self.coordinates = coordinates  # Formato GeoJSON Polygon
        self.timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

    def fetch_satellite_metrics(self) -> dict:
        """
        Extrae datos multiespectrales (Sentinel-2) y de radar (Sentinel-1) 
        para evaluar cambios físicos, hundimientos o degradación estructural.
        """
        roi = ee.Geometry.Polygon(self.coordinates)
        
        # Sentinel-2 (Óptico): Para cambios de uso de suelo / NDBI
        s2_collection = (
            ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED")
            .filterBounds(roi)
            .filterDate("2026-10-01", "2026-11-06")
            .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", 10))
        )
        
        # Cálculo NDBI (Índice de Construcción): Diferencia entre SWIR y NIR
        # NDBI = (SWIR - NIR) / (SWIR + NIR) -> Bandas B11 y B8 en Sentinel-2
        image = s2_collection.median()
        ndbi = image.normalizedDifference(['B11', 'B8']).rename('NDBI')
        mean_ndbi = ndbi.reduceRegion(reducer=ee.Reducer.mean(), geometry=roi, scale=10).getInfo().get('NDBI', 0.0)

        # Simulación de puntuación de integridad estructural (0-100)
        # Un cambio drástico en NDBI indica construcción/demolición no declarada
        structural_integrity_score = round(max(0.0, min(100.0, 100.0 - (abs(mean_ndbi) * 50))), 2)
        
        return {
            "assetId": self.asset_id,
            "evaluationEngine": "Google Earth Engine (Sentinel-2 NDBI / Structural Analysis)",
            "timestamp": self.timestamp,
            "metrics": {
                "meanNDBI": round(mean_ndbi, 4),
                "structuralIntegrityScore": structural_integrity_score,
                "anomalyDetected": structural_integrity_score < 75.0 # Umbral de alerta
            }
        }

    def generate_canonical_qfer(self, evaluation_data: dict) -> str:
        """
        Serializa los datos en JSON Canónico determinista (PTVS v1.0 Standard).
        """
        # Validación estricta del esquema antes del hashing
        validated_report = GEEEvaluationReport(**evaluation_data)
        return json.dumps(validated_report.dict(), sort_keys=True, separators=(',', ':'))

    def compute_sha256_hash(self, canonical_json: str) -> str:
        """
        Genera el hash SHA-256 del informe forense para anclaje on-chain (RFC-003).
        """
        return hashlib.sha256(canonical_json.encode('utf-8')).hexdigest()

# Ejemplo de Ejecución de Prueba
if __name__ == "__main__":
    # Coordenadas de ejemplo: Proyecto Navarrés o similar
    asset_coords = [[[-0.48, 38.45], [-0.47, 38.45], [-0.47, 38.46], [-0.48, 38.46]]]
    
    oracle = GEEPTVSOracle(asset_id="RWA-VALENCIA-PTVS-001", coordinates=asset_coords)
    
    evaluation_result = oracle.fetch_satellite_metrics()
    canonical_data = oracle.generate_canonical_qfer(evaluation_result)
    report_hash = oracle.compute_sha256_hash(canonical_data)
    
    print("=== ORÁCULO SATELITAL GEE-PTVS EJECUTADO ===")
    print(f"Informe Canónico Validado:\n{canonical_data}")
    print(f"\n🔒 Hash SHA-256 de Anclaje On-Chain:\n0x{report_hash}")
