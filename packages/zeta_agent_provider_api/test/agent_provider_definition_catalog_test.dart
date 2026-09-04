import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

const _primaryType = AgentProviderTypeId('fixture.primary');
const _secondaryType = AgentProviderTypeId('fixture.secondary');

const _primaryDefinition = AgentProviderDefinition(
  providerId: 'primary',
  providerType: _primaryType,
  defaultConfig: AgentProviderConfig(
    id: 'primary',
    displayName: 'Primary',
    kind: _primaryType,
    command: 'primary',
  ),
  staticCapabilities: AgentProviderCapabilities.unsupported,
  modelCatalogSourceLabel: 'Primary',
  metricLabel: ZetaMetricLabel.constant('primary'),
  isDefault: true,
);

const _secondaryDefinition = AgentProviderDefinition(
  providerId: 'secondary',
  providerType: _secondaryType,
  defaultConfig: AgentProviderConfig(
    id: 'secondary',
    displayName: 'Secondary',
    kind: _secondaryType,
    command: 'secondary',
  ),
  staticCapabilities: AgentProviderCapabilities.unsupported,
  modelCatalogSourceLabel: 'Secondary',
  metricLabel: ZetaMetricLabel.constant('secondary'),
);

void main() {
  final catalog = AgentProviderDefinitionCatalog(
    const <AgentProviderDefinition>[_primaryDefinition, _secondaryDefinition],
  );

  test('metricLabelFor returns the label declared by a known provider', () {
    expect(
      catalog.metricLabelFor('primary'),
      const ZetaMetricLabel.constant('primary'),
    );
    expect(
      catalog.metricLabelFor('secondary'),
      const ZetaMetricLabel.constant('secondary'),
    );
  });

  test('metricLabelFor hashes unknown and empty provider ids', () {
    expect(
      catalog.metricLabelFor('custom-provider'),
      ZetaMetricLabel.hashed('custom-provider'),
    );
    expect(catalog.metricLabelFor(''), ZetaMetricLabel.hashed(''));
  });
}
