"""Exercise the fixture's fail-closed boundary, not the product backend."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class NativeFixtureBoundary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        os.environ['NATIVE_API_LOG'] = str(Path(cls.temp.name) / 'api.jsonl')
        spec = importlib.util.spec_from_file_location('native_fixture', Path(__file__).with_name('api.py'))
        cls.api = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.api)
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), cls.api.Mock)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.origin = 'http://127.0.0.1:' + str(cls.server.server_address[1])

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.temp.cleanup()

    def request(self, path, body=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        req = Request(self.origin + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
        try:
            response = urlopen(req)
        except HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def test_refuses_non_fictional_identity_and_wrong_password(self):
        for email, password in [('real@example.com', 'Recette-Native!2026'), ('fake@example.invalid', 'incorrect')]:
            code, _ = self.request('/auth/v1/signup', {'email': email, 'password': password})
            self.assertEqual(code, 400)

    def test_login_requires_prior_signup_and_exact_credentials(self):
        email = 'new-native@example.invalid'
        code, _ = self.request('/auth/v1/token?grant_type=password', {'email': email, 'password': 'Recette-Native!2026'})
        self.assertEqual(code, 400)
        code, signup = self.request('/auth/v1/signup', {'email': email, 'password': 'Recette-Native!2026'})
        self.assertEqual(code, 200)
        code, login = self.request('/auth/v1/token?grant_type=password', {'email': email, 'password': 'Recette-Native!2026'})
        self.assertEqual(code, 200)
        self.assertEqual(login['user']['id'], signup['user']['id'])
        code, _ = self.request('/auth/v1/token?grant_type=password', {'email': email, 'password': 'wrong'})
        self.assertEqual(code, 400)

    def test_unknown_api_and_business_writes_are_rejected_and_logged(self):
        _, signup = self.request('/auth/v1/signup', {'email': 'writes@example.invalid', 'password': 'Recette-Native!2026'})
        token = signup['access_token']
        for path in ['/functions/v1/send-sms', '/rest/v1/rpc/not_implemented', '/rest/v1/missions']:
            code, _ = self.request(path, {}, token)
            self.assertEqual(code, 501)
            self.assertEqual(self.api.UNKNOWN[-1]['path'], path)

    def test_protected_read_refuses_unknown_session(self):
        code, _ = self.request('/rest/v1/missions', token='invalid')
        self.assertEqual(code, 401)

    def test_copies_read_is_empty_but_mutations_stay_forbidden(self):
        path = '/rest/v1/rpc/fn_lister_copies_bulletins'
        self.assertEqual(self.request(path, {}, 'invalid')[0], 401)
        _, signup = self.request('/auth/v1/signup', {'email': 'copies@example.invalid', 'password': 'Recette-Native!2026'})
        token = signup['access_token']
        self.assertEqual(self.request(path, {'p_etablissement_id': None, 'p_mission_id': None}, token), (200, []))
        for name in ['fn_reserver_copie_bulletin', 'fn_publier_copie_bulletin_interne', 'fn_retirer_copie_bulletin', 'fn_signaler_copie_bulletin']:
            code, _ = self.request('/rest/v1/rpc/' + name, {}, token)
            self.assertEqual(code, 501)
            self.assertEqual(self.api.UNKNOWN[-1]['path'], '/rest/v1/rpc/' + name)

    def test_signup_does_not_create_a_verified_professional(self):
        _, signup = self.request('/auth/v1/signup', {'email': 'minimal@example.invalid', 'password': 'Recette-Native!2026'})
        token = signup['access_token']
        code, draft = self.request('/rest/v1/rpc/fn_demarrer_inscription', {'p_type_compte': 'SOIGNANT', 'p_profession': 'IDE'}, token)
        self.assertEqual(code, 200)
        self.assertEqual(draft['donnees'], {'profession': 'IDE'})
        self.assertEqual(self.request('/rest/v1/soignants', token=token), (200, []))
        self.assertEqual(self.request('/rest/v1/rpc/fn_mon_profil_soignant_complet', {}, token), (200, {'error': 'Profil introuvable'}))
