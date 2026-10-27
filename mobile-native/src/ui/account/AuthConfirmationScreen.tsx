import { useEffect } from 'react';
import { Text } from 'react-native';
import type { NativeAccountGateway } from '../../account/types';
import { useSession } from '../../session/SessionProvider';
import { ActionButton } from '../components';
import { shared } from '../theme';
import { AccountLayout, useAccountAction } from './components';

/** The root owns the transient URL; do not place it in navigation history or logs. */
export function AuthConfirmationScreen({ url, gateway, onComplete, onBack }: {
  url: string; gateway: NativeAccountGateway; onComplete: () => void; onBack: () => void;
}) {
  const action = useAccountAction();
  const { snapshot } = useSession();
  useEffect(() => {
    if (snapshot.status === 'loading') return;
    void action.run(async () => {
      await gateway.confirmEmail(url);
      if (action.mounted.current) onComplete();
    });
    // The gateway deduplicates consumption of this one-use callback.
  }, [url, gateway, snapshot.status]);
  return <AccountLayout title="Confirmation de l’email" mode={gateway.mode} includeTop>
    <Text style={shared.body}>{action.error ? 'La confirmation n’a pas abouti.' : 'Vérification du lien reçu…'}</Text>
    {action.Error}
    <ActionButton label="Retour à la connexion" secondary disabled={action.busy} onPress={onBack} testID="confirmation-back" />
  </AccountLayout>;
}
