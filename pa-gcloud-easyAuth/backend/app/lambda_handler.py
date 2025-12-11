"""
AWS Lambda handler for FastAPI application
Uses Mangum adapter to wrap FastAPI for Lambda
"""

from mangum import Mangum
from app.main import app

# Create Mangum handler
handler = Mangum(app, lifespan="off")

