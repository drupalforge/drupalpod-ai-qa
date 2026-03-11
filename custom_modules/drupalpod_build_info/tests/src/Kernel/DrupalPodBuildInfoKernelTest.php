<?php

declare(strict_types=1);

namespace Drupal\Tests\drupalpod_build_info\Kernel;

use Drupal\KernelTests\KernelTestBase;
use PHPUnit\Framework\Attributes\RunTestsInSeparateProcesses;

/**
 * Tests DrupalPod build info status report integration.
 *
 * @group drupalpod_build_info
 */
#[RunTestsInSeparateProcesses]
final class DrupalPodBuildInfoKernelTest extends KernelTestBase {

  /**
   * {@inheritdoc}
   */
  protected static $modules = [
    'system',
    'drupalpod_build_info',
  ];

  /**
   * The generated metadata file path used by the module.
   *
   * @var string
   *   Build metadata file path.
   */
  private string $buildInfoPath;

  /**
   * {@inheritdoc}
   */
  protected function setUp(): void {
    parent::setUp();

    // Set the build info path to a temporary location to
    // avoid conflicts with any real metadata.
    $this->buildInfoPath = dirname(DRUPAL_ROOT) . '/build/drupalpod-build-info.json';
  }

  /**
   * {@inheritdoc}
   */
  protected function tearDown(): void {
    if (is_file($this->buildInfoPath)) {
      unlink($this->buildInfoPath);
    }
    parent::tearDown();
  }

  /**
   * Tests the fallback display when metadata has not been generated.
   */
  public function testPreprocessWithoutMetadata(): void {
    $variables = [];

    drupalpod_build_info_preprocess_status_report_general_info($variables);

    $this->assertSame('Unavailable', (string) $variables['drupalpod']['value']);
    $this->assertSame('Run the DrupalPod init workflow to regenerate build metadata.', (string) $variables['drupalpod']['description']);
    $this->assertSame([], $variables['drupalpod']['items']);
  }

  /**
   * Tests formatted build metadata for the DrupalPod card.
   */
  public function testPreprocessWithMetadata(): void {
    $this->writeBuildInfo([
      'generated_at' => '2026-03-09T16:50:36Z',
      'starter_template' => 'core',
      'resolved_core_version' => '11.3.5',
      'compatibility' => 'forced',
      'resolution_mode' => '4',
      'requested_ai_module' => 'ai',
      'requested_ai_version' => '2.0.x',
      'modules' => [
        [
          'machine_name' => 'ai',
          'composer_version' => 'dev-2.0.x',
          'git_ref' => '1.2.1-175-gfc47ddc3',
          'git_branch' => '2.0.x',
        ],
        [
          'machine_name' => 'ai_agents',
          'composer_version' => '1.2.3',
          'git_ref' => '1.2.3',
          'git_branch' => '',
        ],
      ],
    ]);

    // Call the preprocess function to populate variables
    // based on the generated metadata.
    $variables = [];
    drupalpod_build_info_preprocess_status_report_general_info($variables);

    $this->assertSame('', $variables['drupalpod']['value']);
    $this->assertSame('', $variables['drupalpod']['description']);

    $items = $variables['drupalpod']['items'];
    $this->assertSame('Resolution', (string) $items[0]['title']);
    $this->assertSame('compatibility forced, mode 4', $items[0]['value']);
    $this->assertSame('Template', (string) $items[1]['title']);
    $this->assertSame('core, version 11.3.5', $items[1]['value']);
    $this->assertSame('AI target', (string) $items[2]['title']);
    $this->assertSame('ai, version 2.0.x', $items[2]['value']);
    $this->assertSame('Generated', (string) $items[3]['title']);
    $this->assertSame('2026-03-09T16:50:36Z', $items[3]['value']);

    $moduleItem = $items[4];
    $this->assertSame('Modules', (string) $moduleItem['title']);
    $this->assertFalse($moduleItem['open']);

    $this->assertCount(2, $moduleItem['modules']);
    $this->assertSame('ai', $moduleItem['modules'][0]['term']);
    $this->assertSame('branch 2.0.x, composer dev-2.0.x, commit fc47ddc3', $moduleItem['modules'][0]['value']);
    $this->assertSame('git describe 1.2.1-175-gfc47ddc3', (string) $moduleItem['modules'][0]['description']);
    $this->assertSame('ai_agents', $moduleItem['modules'][1]['term']);
    $this->assertSame('tag 1.2.3', $moduleItem['modules'][1]['value']);
    $this->assertArrayNotHasKey('description', $moduleItem['modules'][1]);
  }

  /**
   * Tests that the module overrides the general info template path.
   */
  public function testThemeRegistryAlter(): void {
    // Simulate the theme registry as it would be before alteration.
    $theme_registry = [
      'status_report_general_info' => [
        'path' => 'core/modules/system/templates',
        'template' => 'status-report-general-info',
      ],
    ];

    drupalpod_build_info_theme_registry_alter($theme_registry);

    $this->assertStringEndsWith('drupalpod_build_info/templates', $theme_registry['status_report_general_info']['path']);
    $this->assertSame('status-report-general-info', $theme_registry['status_report_general_info']['template']);
  }

  /**
   * Writes the generated metadata file used by the module.
   *
   * @param array $data
   *   The build metadata to write to the file.
   */
  private function writeBuildInfo(array $data): void {
    $directory = dirname($this->buildInfoPath);
    if (!is_dir($directory)) {
      mkdir($directory, 0777, TRUE);
    }

    // Write the metadata to the expected file path in JSON format.
    file_put_contents($this->buildInfoPath, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
  }

}
