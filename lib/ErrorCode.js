
const RtmpClientConnectionErrorCode = Object.freeze({
	Generic : 1,
	FailedToResolveURL : 2,
	GetSockOptError : 3,
	FailedToConnectSocket : 4,
	ConnectCommandFailed : 5,
	PublishCommandFailed : 6,
	FailedToParseData : 7,
	PeerClosed : 8,
	ReadError : 9,
	PollError : 10
    });

module.exports = RtmpClientConnectionErrorCode;