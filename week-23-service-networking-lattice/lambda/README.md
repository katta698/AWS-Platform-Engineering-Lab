# The two Lambdas that make the point.
#
# backend/   the service being protected. Returns a rate. Has no idea who
#            called it and performs no check of its own -- that is the whole
#            argument: the authorisation happened before the request arrived.
#
# client/    the caller. Signs its request with SigV4 using whatever role it
#            has been given, so swapping the role is the entire difference
#            between an allowed call and a denied one.
