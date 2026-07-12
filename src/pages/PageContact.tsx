import { useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Mail, Send, CheckCircle } from 'lucide-react';
import { CaptchaTurnstile, TURNSTILE_REQUIRED } from '@/components/CaptchaTurnstile';

export default function PageContact() {
  usePageTitle('Contact');
  const [form, setForm] = useState({ nom: '', email: '', sujet: '', message: '', hp: '' });
  const [envoi, setEnvoi] = useState(false);
  const [envoye, setEnvoye] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);
  const [captchaKey, setCaptchaKey] = useState(0);

  const maj = (champ: string, valeur: string) => setForm((f) => ({ ...f, [champ]: valeur }));

  const envoyer = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.nom.trim() || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email) || form.message.trim().length < 5) {
      toast.error('Merci de renseigner votre nom, un email valide et un message.');
      return;
    }
    setEnvoi(true);
    if (TURNSTILE_REQUIRED && !turnstileToken) {
      toast.error('Merci de confirmer que vous n’êtes pas un robot.');
      setEnvoi(false);
      return;
    }
    const { data, error } = await supabase.functions.invoke('contact-form', { body: { ...form, turnstileToken } });
    setEnvoi(false);
    setTurnstileToken(null);
    setCaptchaKey((k) => k + 1);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Envoi impossible, réessayez plus tard.');
      return;
    }
    setEnvoye(true);
    toast.success('Message envoyé — nous vous répondons rapidement.');
  };

  return (
    <>
      <SEOHead
        title="Contact | Jolene Santé"
        description="Une question sur Jolene Santé ? Contactez l'équipe directement via le formulaire ou par email à support@jolene.app."
        url="https://jolene.app/contact"
      />
      <SEOPageLayout
        heroTitle="Une question ? Écrivez-nous."
        heroSubtitle="L'équipe Jolene Santé vous répond rapidement — établissements, soignants, presse ou partenariats."
        ctaText="Retour à l'accueil"
        ctaHref="/"
      >
        <section className="py-12 md:py-16">
          <div className="max-w-2xl mx-auto px-4">
            <CardY2K hoverLift={false}>
              <CardY2KContent>
                {envoye ? (
                  <div className="text-center py-8">
                    <CheckCircle className="h-12 w-12 text-primary mx-auto mb-4" />
                    <h2 className="text-xl font-bold text-foreground mb-2">Message envoyé</h2>
                    <p className="text-muted-foreground">Merci {form.nom.split(' ')[0]} — nous vous répondons sur {form.email} au plus vite.</p>
                  </div>
                ) : (
                  <form onSubmit={envoyer} className="space-y-4">
                    {/* Honeypot anti-bot (caché) */}
                    <input
                      type="text" tabIndex={-1} autoComplete="off"
                      value={form.hp} onChange={(e) => maj('hp', e.target.value)}
                      className="absolute -left-[9999px]" aria-hidden="true"
                    />
                    <div className="grid sm:grid-cols-2 gap-4">
                      <div>
                        <Label htmlFor="contact-nom">Votre nom *</Label>
                        <Input id="contact-nom" value={form.nom} onChange={(e) => maj('nom', e.target.value)} placeholder="Prénom Nom" required />
                      </div>
                      <div>
                        <Label htmlFor="contact-email">Votre email *</Label>
                        <Input id="contact-email" type="email" value={form.email} onChange={(e) => maj('email', e.target.value)} placeholder="vous@exemple.fr" required />
                      </div>
                    </div>
                    <div>
                      <Label htmlFor="contact-sujet">Sujet</Label>
                      <Input id="contact-sujet" value={form.sujet} onChange={(e) => maj('sujet', e.target.value)} placeholder="Le sujet de votre message" />
                    </div>
                    <div>
                      <Label htmlFor="contact-message">Message *</Label>
                      <Textarea id="contact-message" rows={6} value={form.message} onChange={(e) => maj('message', e.target.value)} placeholder="Comment pouvons-nous vous aider ?" required />
                    </div>
                    <CaptchaTurnstile
                      key={captchaKey}
                      className="flex justify-center"
                      onVerify={setTurnstileToken}
                      onExpire={() => setTurnstileToken(null)}
                      onError={() => setTurnstileToken(null)}
                    />
                    <BoutonY2K type="submit" disabled={envoi || (TURNSTILE_REQUIRED && !turnstileToken)} loading={envoi} iconeGauche={envoi ? undefined : <Send className="h-4 w-4" />} className="w-full">
                      {envoi ? 'Envoi…' : 'Envoyer le message'}
                    </BoutonY2K>
                  </form>
                )}
              </CardY2KContent>
            </CardY2K>

            <p className="text-center text-sm text-muted-foreground mt-6 flex items-center justify-center gap-2">
              <Mail className="h-4 w-4 text-primary" />
              Ou par email :{' '}
              <a href="mailto:support@jolene.app" className="text-primary hover:underline font-medium">support@jolene.app</a>
            </p>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
