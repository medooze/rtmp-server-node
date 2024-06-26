
const RtmpClientConnectionErrorCode = Object.freeze({
	NoError: 0,
	Generic : 1,
	FailedToResolveURL : 2,
	GetSockOptError : 3,
	FailedToConnectSocket : 4,
	ConnectCommandFailed : 5,
	FailedToParseData : 6,
	PeerClosed : 7,
	ReadError : 8,
	PollError : 9,
	TlsInitError: 10,
	TlsHandshakeError : 11,
	TlsDecryptError : 12,
	TlsEncryptError : 13
    });

module.exports = RtmpClientConnectionErrorCode;
