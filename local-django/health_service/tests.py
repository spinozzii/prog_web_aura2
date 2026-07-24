from django.test import SimpleTestCase
from django.urls import reverse


class HealthContractTests(SimpleTestCase):
    def test_health_contract(self):
        response = self.client.get(reverse("health"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "application/json; charset=utf-8")
        self.assertJSONEqual(response.content, {
            "apiVersion": "1.0", "service": "local-django", "status": "ok"
        })
