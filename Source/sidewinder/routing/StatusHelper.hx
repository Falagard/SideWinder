package sidewinder.routing;

import snake.http.HTTPStatus;

class StatusHelper {
    public static function getStatus(code:Int):HTTPStatus {
        return switch (code) {
            case 200: HTTPStatus.OK;
            case 201: HTTPStatus.CREATED;
            case 202: HTTPStatus.ACCEPTED;
            case 204: HTTPStatus.NO_CONTENT;
            case 400: HTTPStatus.BAD_REQUEST;
            case 401: HTTPStatus.UNAUTHORIZED;
            case 403: HTTPStatus.FORBIDDEN;
            case 404: HTTPStatus.NOT_FOUND;
            case 409: HTTPStatus.CONFLICT;
            case 429: HTTPStatus.TOO_MANY_REQUESTS;
            case 500: HTTPStatus.INTERNAL_SERVER_ERROR;
            case 502: HTTPStatus.BAD_GATEWAY;
            case 503: HTTPStatus.SERVICE_UNAVAILABLE;
            case 504: HTTPStatus.GATEWAY_TIMEOUT;
            default: HTTPStatus.INTERNAL_SERVER_ERROR;
        }
    }
}
