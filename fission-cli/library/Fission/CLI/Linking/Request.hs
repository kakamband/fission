module Fission.CLI.Linking.Request (requestFrom) where

import           Crypto.Cipher.AES                         (AES256)
import qualified Crypto.PubKey.RSA.Types                   as RSA

import           Servant.Client.Core

import           Fission.Prelude

import           Fission.Authorization.Potency.Types
import           Fission.User.DID.Types

import           Fission.Key.Asymmetric.Public.Types
import qualified Fission.Key.Symmetric                     as Symmetric

import           Fission.Web.Auth.Token.Bearer.Types       as Bearer
import           Fission.Web.Auth.Token.JWT                as JWT
import qualified Fission.Web.Auth.Token.JWT                as UCAN
import qualified Fission.Web.Auth.Token.JWT.Error          as JWT
import qualified Fission.Web.Auth.Token.JWT.Resolver.Class as JWT
import qualified Fission.Web.Auth.Token.JWT.Resolver.Error as UCAN.Resolver
import qualified Fission.Web.Auth.Token.JWT.Validation     as UCAN
import qualified Fission.Web.Auth.Token.UCAN               as UCAN

import           Fission.PubSub                            as PubSub
import           Fission.PubSub.Secure                     as PubSub.Secure

import qualified Fission.CLI.Linking.PIN                   as PIN

type AESPayload m expected = SecurePayload m (Symmetric.Key AES256) expected
type RSAPayload m expected = SecurePayload m RSA.PrivateKey expected

requestFrom ::
  ( MonadLogger       m
  , MonadIO           m
  , MonadTime         m
  , JWT.Resolver      m
  , MonadPubSubSecure m (Symmetric.Key AES256)
  , MonadPubSubSecure m RSA.PrivateKey
  , MonadRescue       m
  , m `Raises` String
  , m `Raises` JWT.Error
  , m `Raises` UCAN.Resolver.Error
  , ToJSON   (AESPayload m PIN.PIN) -- FIXME can make cleaner with a constraint alias on pubsubsecure
  , FromJSON (AESPayload m Token)
  , FromJSON (RSAPayload m (Symmetric.Key AES256))
  )
  => DID
  -> DID
  -> m ()
requestFrom targetDID myDID =
  PubSub.connect baseURL topic \conn -> reattempt 10 do
    aesKey <- secureConnection conn () \rsaConn@SecureConnection {key} ->
      reattempt 10 do
        broadcast conn $ DID Key (RSAPublicKey $ RSA.private_pub key) -- STEP 2

        reattempt 10 do
          -- STEP 3
          aesKey      <- secureListen rsaConn
          bearerToken <- secureListen SecureConnection {conn, key = aesKey}-- sessionKey

          -- STEP 4
          validateProof bearerToken targetDID myDID aesKey
          return aesKey

    let aesConn = SecureConnection {conn, key = aesKey}

    -- Step 5
    pin <- PIN.create
    secureBroadcast aesConn pin

    -- STEP 6
    reattempt 100 do
      Bearer.Token {..} <- secureListen aesConn
      ensureM $ UCAN.check myDID rawContent jwt
      UCAN.JWT {claims = UCAN.Claims {sender}} <- ensureM $ UCAN.getRoot jwt

      if sender == targetDID
        then storeUCAN rawContent
        else raise "no ucan" -- FIXME

  where
    topic   = PubSub.Topic $ textDisplay targetDID
    baseURL = BaseUrl Https "runfission.net" 443 "/user/link"

validateProof ::
  ( MonadIO      m
  , MonadTime    m
  , JWT.Resolver m
  , MonadRaise   m
  , m `Raises` JWT.Error
  , m `Raises` String -- FIXME better error
  )
  => Bearer.Token
  -> DID
  -> DID
  -> Symmetric.Key AES256
  -> m UCAN.JWT
validateProof Bearer.Token {..} myDID targetDID sessionAES = do
  ensureM $ UCAN.check myDID rawContent jwt

  case (jwt |> claims |> potency) == AuthNOnly of
    False ->
      raise "Not a closed UCAN" -- FIXME

    True ->
      case (jwt |> claims |> facts) of
        (SessionKey aesFact : _) ->
          case aesFact == sessionAES of
            False -> raise "Sesison key doesn't match! ABORT!"
            True  -> ensureM $ UCAN.check targetDID rawContent jwt

        _ ->
          raise "No session key fact" -- FIXME

storeUCAN :: MonadIO m => UCAN.RawContent -> m ()
storeUCAN = undefined

storeWNFSKeyFor :: Monad m => DID -> FilePath -> Symmetric.Key AES256 -> m ()
storeWNFSKeyFor did path aes = undefined
