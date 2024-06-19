
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
	TlsInitError: 10
    });

module.exports = RtmpClientConnectionErrorCode;
