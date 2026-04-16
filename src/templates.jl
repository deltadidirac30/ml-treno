# ============================================================================
# This file defines real Italian railway route templates.
# 
# These templates represent actual railway routes in Italy with their
# characteristic properties (length, number of stops, average slope, etc.).
# They are used when explicit_param == "template_id" to generate realistic
# profiles based on real routes.
# ============================================================================


# ============================================================================
# Array of real Italian railway routes.
# Each tuple contains:
#   - id: Unique identifier for the route
#   - name: Human-readable route name
#   - L_km: Typical route length in kilometers
#   - slope_style: Symbol describing the slope characteristics
#   - v_max: Maximum allowed speed on this route (km/h)
#   - n_stops: Typical number of stops on this route
#   - slope_mean: Average slope (permille, positive = uphill)
#   - slope_range: (min, max) slope values (permille)
# 
# Examples of routes:
#   1. Torino-Milano: Flat route (1 permille average)
#   2. Brennero-Verona: Mountainous, mostly downhill (-8 permille)
#   3. Brescia-Iseo-Edolo: Very mountainous (30 permille range)
# ============================================================================
const REAL_ROUTE_TEMPLATES = [
    (id=1, name="Torino-Milano",           L_km=125.0, slope_style=:pianura,     v_max=150.0, n_stops=4,  slope_mean=1.0,  slope_range=(-5.0, 5.0)),
    (id=2, name="Napoli-Reggio Calabria",  L_km=495.0, slope_style=:costiero,    v_max=140.0, n_stops=8,  slope_mean=3.0,  slope_range=(-15.0, 15.0)),
    (id=3, name="Brennero-Verona",         L_km=233.0, slope_style=:discendente, v_max=120.0, n_stops=6,  slope_mean=-8.0, slope_range=(-25.0, 10.0)),
    (id=4, name="Roma-Ancona",             L_km=295.0, slope_style=:appenninica, v_max=130.0, n_stops=10, slope_mean=2.0,  slope_range=(-20.0, 20.0)),
    (id=5, name="Palermo-Messina",         L_km=230.0, slope_style=:costiero,    v_max=100.0, n_stops=12, slope_mean=1.5,  slope_range=(-10.0, 10.0)),
    (id=6, name="Brescia-Iseo-Edolo",      L_km=103.0, slope_style=:montano,     v_max=80.0,  n_stops=15, slope_mean=5.0,  slope_range=(-30.0, 30.0)),
]


# ============================================================================
# Returns the template for a given row index.
# 
# Since we have 6 templates and potentially many rows, we cycle through
# them using modulo: row 1 -> template 1, row 7 -> template 1, etc.
# 
# INPUT:
#   - row_idx: The row index (1-based)
# OUTPUT:
#   - The template tuple for that row
# 
# Example:
#   template_for_row(1) -> Torino-Milano
#   template_for_row(7) -> Torino-Milano (wraps around)
# ============================================================================
template_for_row(row_idx::Int) = REAL_ROUTE_TEMPLATES[mod1(row_idx, 6)]