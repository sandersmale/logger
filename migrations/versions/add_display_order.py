"""Add display_order to station

Revision ID: add_display_order
Create Date: 2025-03-29

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers
revision = 'add_display_order'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # Voeg display_order kolom toe aan de station tabel
    op.add_column('station', sa.Column('display_order', sa.Integer(), server_default='999'))
    
    # Update bestaande stations met een oplopende volgorde
    # We gebruiken raw SQL omdat we direct met de database willen werken
    conn = op.get_bind()
    
    # Haal eerst de bestaande stations op, gesorteerd op naam
    result = conn.execute(sa.text("SELECT id FROM station ORDER BY name"))
    stations = result.fetchall()
    
    # Wijs oplopende display_order toe aan bestaande stations
    for i, (station_id,) in enumerate(stations):
        conn.execute(
            sa.text("UPDATE station SET display_order = :order WHERE id = :id"),
            {"order": i + 1, "id": station_id}
        )


def downgrade():
    # Verwijder de kolom als we terugdraaien
    op.drop_column('station', 'display_order')