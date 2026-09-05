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
  icon: AgentProviderSvgIcon(
    packageName: 'fixture_primary',
    assetPath: 'assets/icon.svg',
  ),
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

  test('static branding is optional and never enters persisted settings', () {
    expect(
      catalog.definitionForProviderId('primary')?.icon,
      same(_primaryDefinition.icon),
    );
    expect(
      catalog.definitionForType(_primaryType)?.icon,
      same(_primaryDefinition.icon),
    );
    expect(catalog.definitionForProviderId('secondary')?.icon, isNull);
    expect(_primaryDefinition.icon?.colorPolicy, AgentIconColorPolicy.themed);
    expect(
      catalog.defaultSettings.toJson().toString(),
      isNot(contains('assets/icon.svg')),
    );
    expect(
      catalog.defaultSettings.toJson().toString(),
      isNot(contains('fixture_primary')),
    );
  });

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
