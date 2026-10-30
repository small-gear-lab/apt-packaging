#ifndef NGTCP2_CRYPTO_RUSTLS_H
#define NGTCP2_CRYPTO_RUSTLS_H
#include <ngtcp2/ngtcp2_crypto.h>
#include <rustls.h>

/* Prepare the crypto primitives (OpenSSL libcrypto); call once. */
int ngtcp2_crypto_rustls_init(void);

typedef struct ngtcp2_crypto_rustls_session ngtcp2_crypto_rustls_session;

/* A TLS session for one client connection. `conn_ref` is what the ngtcp2 helper uses to find
 * the ngtcp2_conn. The rustls connection is created when ngtcp2 hands over the local transport
 * parameters. Pass the session to ngtcp2_conn_set_tls_native_handle(). */
ngtcp2_crypto_rustls_session *ngtcp2_crypto_rustls_session_new(
    const struct rustls_client_config *config, ngtcp2_crypto_conn_ref *conn_ref,
    const char *server_name, const uint8_t *alpn, size_t alpnlen);
void ngtcp2_crypto_rustls_session_free(ngtcp2_crypto_rustls_session *s);

/* The DER of the i-th certificate that the server sent (0 is the end-entity certificate), valid as long as the session
 * is. Returns 0, or -1 when there is none (the handshake has not got that far, or i is past the last). */
int ngtcp2_crypto_rustls_session_peer_certificate(
    const ngtcp2_crypto_rustls_session *s, size_t i, const uint8_t **der,
    size_t *len);
#endif
