#!/usr/bin/env python3
"""Servidor local de Control de Gastos.

Abre la plataforma en http://localhost:8765 y lee el portal Wi-Fi de
Registro Contable (Money Manager) en tu red, para que la sincronización
sea: pegar el enlace que muestra el iPhone y presionar Sincronizar.

Solo usa la biblioteca estándar de Python 3. Uso:
    python3 servidor.py              # abre el navegador
    python3 servidor.py --no-abrir   # sin abrir el navegador

Opcional: crea un archivo servidor.json junto a este archivo para permitir
que tu página de GitHub Pages también use el servidor:
    {"permitir": ["https://tu-usuario.github.io"], "puerto": 8765}
"""
import ipaddress
import json
import os
import re
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

DIR = os.path.dirname(os.path.abspath(__file__))
CONF_PATH = os.path.join(DIR, 'servidor.json')
try:
    with open(CONF_PATH, encoding='utf-8') as f:
        CONF = json.load(f)
except FileNotFoundError:
    CONF = {}
except Exception as e:  # noqa: BLE001
    print(f'No pude leer servidor.json: {e}')
    CONF = {}

PUERTO = int(os.environ.get('CG_PUERTO') or CONF.get('puerto') or 8765)
PERMITIR = {o.rstrip('/') for o in CONF.get('permitir', [])}
PERMITIR_LOOPBACK = os.environ.get('CG_PERMITIR_LOOPBACK') == '1'  # solo para pruebas
ARCHIVOS = {'/': 'index.html', '/index.html': 'index.html', '/config.js': 'config.js', '/README.md': 'README.md'}
FECHA = re.compile(r'^\d{4}-\d{2}-\d{2}$')
VERSION = 1
# El portal está en tu red local: se conecta directo, sin proxies del sistema.
SIN_PROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def ips_locales():
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('10.255.255.255', 1))
        ips.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    return sorted(ip for ip in ips if not ip.startswith('127.'))


def direccion_privada(host):
    """True si host es una IP de red local (192.168.x, 10.x, 172.16-31.x)."""
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    if ip.is_loopback:
        return PERMITIR_LOOPBACK
    return ip.is_private and not ip.is_link_local and not ip.is_multicast


def host_valido(host_header):
    """Protege contra páginas externas que intenten usar el servidor (DNS rebinding)."""
    host = (host_header or '').strip().lower()
    if host.startswith('['):
        host = host[1:host.find(']')]
    else:
        host = host.rsplit(':', 1)[0] if host.count(':') == 1 else host
    if host in ('localhost', '127.0.0.1', '::1') or host.endswith('.local'):
        return True
    try:
        return ipaddress.ip_address(host).is_private
    except ValueError:
        return False


class Manejador(SimpleHTTPRequestHandler):
    server_version = 'ControlGastos/1'

    def log_message(self, fmt, *args):
        if '/api/' in (self.path or ''):
            sys.stdout.write('%s  %s\n' % (time.strftime('%H:%M:%S'), fmt % args))

    def origen_permitido(self):
        origen = (self.headers.get('Origin') or '').rstrip('/')
        return origen if origen and origen in PERMITIR else None

    def cabeceras_cors(self):
        origen = self.origen_permitido()
        if origen:
            self.send_header('Access-Control-Allow-Origin', origen)
            self.send_header('Vary', 'Origin')
            self.send_header('Access-Control-Allow-Private-Network', 'true')
            self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def responder(self, codigo, cuerpo, tipo='application/json; charset=utf-8'):
        datos = cuerpo.encode('utf-8') if isinstance(cuerpo, str) else cuerpo
        self.send_response(codigo)
        self.send_header('Content-Type', tipo)
        self.send_header('Content-Length', str(len(datos)))
        self.send_header('Cache-Control', 'no-store')
        self.cabeceras_cors()
        self.end_headers()
        self.wfile.write(datos)

    def error_json(self, codigo, mensaje):
        self.responder(codigo, json.dumps({'error': mensaje}, ensure_ascii=False))

    def do_OPTIONS(self):  # noqa: N802
        if not host_valido(self.headers.get('Host')):
            return self.error_json(403, 'Host no permitido')
        self.send_response(204 if self.origen_permitido() else 403)
        self.cabeceras_cors()
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):  # noqa: N802
        if not host_valido(self.headers.get('Host')):
            return self.error_json(403, 'Host no permitido')
        url = urllib.parse.urlsplit(self.path)
        if url.path.startswith('/api/'):
            origen = self.headers.get('Origin')
            mismo = origen is None or origen.rstrip('/') in (f'http://{self.headers.get("Host")}',)
            if not mismo and not self.origen_permitido():
                return self.error_json(403, 'Esta página no tiene permiso para usar el servidor local.')
            if url.path == '/api/ping':
                return self.responder(200, json.dumps({'ok': True, 'version': VERSION, 'ips': ips_locales(), 'puerto': PUERTO}))
            if url.path == '/api/portal':
                return self.leer_portal(urllib.parse.parse_qs(url.query))
            return self.error_json(404, 'Ruta desconocida')
        nombre = ARCHIVOS.get(url.path)
        if not nombre:
            return self.error_json(404, 'No encontrado')
        ruta = os.path.join(DIR, nombre)
        try:
            with open(ruta, 'rb') as f:
                datos = f.read()
        except FileNotFoundError:
            return self.error_json(404, f'Falta el archivo {nombre}')
        tipo = {'.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8'}.get(os.path.splitext(nombre)[1], 'text/markdown; charset=utf-8')
        self.responder(200, datos, tipo)

    def leer_portal(self, q):
        base = (q.get('base') or [''])[0].strip()
        desde = (q.get('desde') or [''])[0]
        hasta = (q.get('hasta') or [''])[0]
        if not re.match(r'^https?://', base, re.I):
            base = 'http://' + base
        partes = urllib.parse.urlsplit(base)
        host = partes.hostname or ''
        if not direccion_privada(host):
            return self.error_json(400, 'La dirección debe ser la que muestra la app en tu red local (por ejemplo 192.168.1.20:8888).')
        if not (FECHA.match(desde) and FECHA.match(hasta)):
            return self.error_json(400, 'Fechas no válidas.')
        destino = urllib.parse.urlunsplit((partes.scheme or 'http', partes.netloc, '/moneyBook/getDataByPeriod',
                                           urllib.parse.urlencode({'startDate': desde, 'endDate': hasta, 'mbid': '1', 'assetId': ''}), ''))
        inicio = time.time()
        try:
            with SIN_PROXY.open(urllib.request.Request(destino, headers={'User-Agent': 'ControlGastos'}), timeout=40) as r:
                xml = r.read()
        except urllib.error.HTTPError as e:
            return self.error_json(502, f'El portal respondió con error {e.code}. Revisa que sea la dirección de Registro Contable.')
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError, OSError):
            return self.error_json(504, 'El iPhone no respondió. Revisa que la app esté abierta con el servicio Wi-Fi activo, '
                                        'que el teléfono esté desbloqueado y en el mismo Wi-Fi que esta Mac, y que la dirección sea la actual.')
        if b'<dataset' not in xml[:500]:
            return self.error_json(502, 'Esa dirección respondió, pero no parece ser el portal de Registro Contable.')
        print('%s  Portal leído: %d KB en %.1f s' % (time.strftime('%H:%M:%S'), len(xml) // 1024, time.time() - inicio))
        self.responder(200, xml, 'text/xml; charset=utf-8')


def main():
    try:
        servidor = ThreadingHTTPServer(('0.0.0.0', PUERTO), Manejador)
    except OSError:
        print(f'El puerto {PUERTO} ya está en uso. ¿Ya tienes el servidor abierto en otra ventana?')
        webbrowser.open(f'http://localhost:{PUERTO}/')
        sys.exit(1)
    print('Control de Gastos está corriendo.')
    print(f'  En esta Mac:      http://localhost:{PUERTO}/')
    for ip in ips_locales():
        print(f'  Desde el iPhone:  http://{ip}:{PUERTO}/   (mismo Wi-Fi)')
    if PERMITIR:
        print('  También acepta:   ' + ', '.join(sorted(PERMITIR)))
    print('Deja esta ventana abierta mientras uses la plataforma. Para salir: Ctrl+C')
    if '--no-abrir' not in sys.argv:
        threading.Timer(0.8, lambda: webbrowser.open(f'http://localhost:{PUERTO}/')).start()
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        print('\nServidor detenido.')


if __name__ == '__main__':
    main()
