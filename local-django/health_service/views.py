from django.http import JsonResponse
from django.views.decorators.http import require_GET


@require_GET
def health(request):
    return JsonResponse(
        {"apiVersion": "1.0", "service": "local-django", "status": "ok"},
        content_type="application/json; charset=utf-8",
    )
