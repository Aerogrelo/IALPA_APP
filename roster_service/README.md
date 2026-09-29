# IALPA App — Roster Parser Service

Servicio pequeño que recibe el PDF del roster de un piloto, lo parsea y
devuelve el resultado en JSON. **No guarda el PDF**: se procesa en un
fichero temporal que se borra inmediatamente después, tanto si el
parseo tiene éxito como si falla.

## Probarlo en local

```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

Luego, con la app corriendo en `http://127.0.0.1:8000`:

```bash
curl -X POST http://127.0.0.1:8000/parse-roster \
  -H "X-API-Key: lo-que-pongas-en-ROSTER_API_KEY" \
  -F "file=@/ruta/a/tu-roster.pdf"
```

## Desplegarlo (Render, capa gratuita)

1. Crea una cuenta en [render.com](https://render.com) (gratis).
2. "New +" → "Web Service" → conecta este repositorio (o sube esta
   carpeta `roster_service/` como su propio repo en GitHub).
3. Render detecta Python automáticamente. Configura:
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`
4. En "Environment", añade la variable `ROSTER_API_KEY` con un valor
   secreto que tú elijas (una contraseña larga cualquiera). Este mismo
   valor se lo daremos luego a la app Flutter para que solo ella pueda
   usar el servicio.
5. Deploy. Render te da una URL tipo
   `https://ialpa-roster-parser.onrender.com`.
6. Comprueba que funciona: `https://tu-url.onrender.com/health` debería
   devolver `{"status": "ok"}`.

**Nota sobre la capa gratuita de Render**: el servicio "se duerme" tras
un rato sin uso, y la primera petición después de dormir tarda unos
segundos más (arranque en frío). Para un piloto probando el roster de
vez en cuando, es perfectamente aceptable. Si en el futuro se usa mucho
más, se puede pasar a un plan de pago (siempre económico, unos $7/mes)
para que no se duerma.

## Formato de respuesta

```json
{
  "days": {
    "01/07": {"status": "ok", "kind": "F"},
    "02/07": {
      "status": "ok",
      "reportTime": "06:30",
      "standbys": [],
      "legs": [
        {
          "flightNumber": "EI123",
          "offBlock": "07:15",
          "offBlockActual": true,
          "origin": "DUB",
          "destination": "MAD",
          "onBlock": "10:05",
          "onBlockActual": true,
          "aircraft": "320"
        }
      ],
      "delays": [],
      "trailingTime": "18:40",
      "flags": []
    }
  }
}
```

`status` puede ser `ok`, `empty` (día sin nada) o `needs_review`
(el parser encontró algo que no reconoce con confianza — en ese caso
`flags` explica qué, y la app debería pedir al piloto que introduzca
esos datos a mano en lugar de arriesgarse a adivinar).
