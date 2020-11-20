module Fission.Key.Symmetric.Types (Key (..)) where

import qualified System.IO.Unsafe           as Unsafe

import           Crypto.Cipher.AES          (AES256)
import           Crypto.Cipher.Types        (blockSize)
import           Crypto.Random.Types

import           Fission.Prelude

import           Fission.Key.GenData.Family

newtype Key cipher = Key { rawKey :: ByteString }
  deriving newtype Eq

type instance GenData (Key cipher) = ()

instance Arbitrary (Key AES256) where
  arbitrary = return $ Key aes
    where
      aes = Unsafe.unsafePerformIO $ getRandomBytes (blockSize (undefined :: AES256))

instance Display (Key AES256) where
  display (Key bs) = displayBytesUtf8 bs

instance ToJSON (Key AES256) where
  toJSON (Key bs) = String $ decodeUtf8Lenient bs

instance FromJSON (Key AES256) where
  parseJSON = withText "AES256 SymmetricKey" \txt ->
    return . Key $ encodeUtf8 txt